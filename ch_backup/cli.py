# -*- coding: utf-8 -*-
"""
Command-line interface.
"""

import re
import sys
import uuid
from functools import wraps
from typing import Union

from click import (Choice, Context, ParamType, Path, argument, group, option, pass_context)
from click.types import StringParamType
from tabulate import tabulate

from . import logging
from .backup.metadata import BackupState
from .ch_backup import ClickhouseBackup
from .config import Config
from .util import drop_privileges, setup_environment, utcnow
from .version import get_version

TIMESTAMP = utcnow().strftime('%Y%m%dT%H%M%S')
UUID = str(uuid.uuid4())


@group(context_settings={
    'help_option_names': ['-h', '--help'],
    'terminal_width': 100,
})
@option('-c',
        '--config',
        type=Path(exists=True),
        default='/etc/yandex/ch-backup/ch-backup.conf',
        help='Configuration file path.')
@option('--protocol', type=Choice(['http', 'https']), help='Protocol used to connect to ClickHouse server.')
@option('--port', type=int, help='Port used to connect to ClickHouse server.')
@option('--ca-path', type=str, help='Path to custom CA bundle path for https protocol.')
@option('--insecure', is_flag=True, help='Disable certificate verification for https protocol.')
@pass_context
def cli(ctx: Context, config: str, protocol: str, port: int, ca_path: Union[str, bool], insecure: bool) -> None:
    """Tool for managing ClickHouse backups."""
    if insecure:
        ca_path = False

    cfg = Config(config)
    if protocol is not None:
        cfg['clickhouse']['protocol'] = protocol
    if port is not None:
        cfg['clickhouse']['port'] = port
    if ca_path is not None:
        cfg['clickhouse']['ca_path'] = ca_path

    logging.configure(cfg['logging'])
    setup_environment(cfg['main'])

    if not drop_privileges(cfg['main']):
        logging.warning('Drop privileges was disabled in config file.')

    ch_backup = ClickhouseBackup(cfg)

    ctx.obj = dict(backup=ch_backup)


def command(*args, **kwargs):
    """
    Decorator for ch-backup cli commands.
    """

    def decorator(f):
        @pass_context
        @wraps(f)
        def wrapper(ctx, *args, **kwargs):
            try:
                logging.info('Executing command \'%s\', params: %s, args %s', ctx.command.name, {
                    **ctx.parent.params,
                    **ctx.params,
                }, ctx.args)
                result = ctx.invoke(f, ctx, ctx.obj['backup'], *args, **kwargs)
                logging.info('Command \'%s\' completed', ctx.command.name)
                return result
            except Exception:
                logging.exception('Command \'%s\' failed', ctx.command.name)
                raise

        return cli.command(*args, **kwargs)(wrapper)

    return decorator


class List(ParamType):
    """
    List type for command-line parameters.
    """
    name = 'list'

    def __init__(self, separator=',', regexp=None):
        self.separator = separator
        self.regexp_str = regexp
        self.regexp = re.compile(regexp) if regexp else None

    def convert(self, value, param, ctx):
        """
        Convert input value into list of items.
        """
        try:
            result = value.split(self.separator)

            if self.regexp:
                for item in result:
                    if self.regexp.fullmatch(item) is None:
                        raise ValueError()

            return result

        except ValueError:
            msg = f'"{value}" is not a valid list of items'
            if self.regexp:
                msg += f' matching the format: {self.regexp_str}'

            self.fail(msg, param, ctx)


class String(StringParamType):
    """
    String type for command-line parameters with support of macros and
    regexp-based validation.
    """
    name = 'string'

    def __init__(self, regexp=None, macros=None):
        self.regexp_str = regexp
        self.regexp = re.compile(regexp) if regexp else None
        self.macros = macros

    def convert(self, value, param, ctx):
        """
        Parse input value.
        """
        if self.macros:
            for macro, replacement in self.macros.items():
                value = value.replace(macro, replacement)

        if self.regexp:
            if self.regexp.fullmatch(value) is None:
                msg = f'"{value}" does not match the format: {self.regexp_str}'
                self.fail(msg, param, ctx)

        return super().convert(value, param, ctx)


@command(name='list')
@option('-a',
        '--all',
        is_flag=True,
        default=False,
        help='List all backups. The default is to show only successfully created backups.')
@option('-v', '--verbose', is_flag=True, default=False, help='Verbose output.')
def list_command(_ctx: Context, ch_backup: ClickhouseBackup, verbose: bool, **kwargs: dict) -> None:
    """List existing backups."""
    state = None if kwargs['all'] else BackupState.CREATED

    backups = ch_backup.list(state)

    if not verbose:
        print('\n'.join([b.name for b in backups]))
        return

    fields = ('name', 'state', 'start_time', 'end_time', 'size', 'real_size', 'ch_version')

    report = []
    state_idx = fields.index('state')
    for backup in backups:
        entry_report = [str(getattr(backup, x, None)) for x in fields]
        entry_report[state_idx] = backup.state.value
        report.append(entry_report)

    print(tabulate(report, headers=fields))


@command(name='show')
@argument('name', metavar='BACKUP')
def show_command(ctx: Context, ch_backup: ClickhouseBackup, name: str) -> None:
    """Show details for a particular backup."""
    name = _validate_name(ctx, ch_backup, name)

    print(ch_backup.get(name))


@command(name='backup')
@option('--name',
        type=String(regexp=r'(?a)[\w-]+', macros={
            '{timestamp}': TIMESTAMP,
            '{uuid}': UUID,
        }),
        help='Name of creating backup. The value can contain macros:'
        f' {{timestamp}} - current time in UTC ({TIMESTAMP}),'
        f' {{uuid}} - randomly generated UUID value ({UUID}).',
        default='{timestamp}')
@option('-d', '--databases', type=List(regexp=r'\w+'), help='Comma-separated list of databases to backup.')
@option('-t', '--tables', type=List(regexp=r'[\w.]+'), help='Comma-separated list of tables to backup.')
@option('-f', '--force', is_flag=True, help='Enables force mode (backup.min_interval is ignored).')
@option('-l', '--label', multiple=True, help='Custom labels as key-value pairs that represents user metadata.')
def backup_command(ctx: Context, ch_backup: ClickhouseBackup, name: str, databases: list, tables: list, force: bool,
                   label: list) -> None:
    """Perform backup."""
    if databases and tables:
        ctx.fail('Options --databases and --tables are mutually exclusive.')

    labels = {}
    for key_value_str in label:
        key_value = key_value_str.split('=', 1)
        key = key_value.pop(0)
        value = key_value.pop() if key_value else None
        labels[key] = value

    (name, msg) = ch_backup.backup(name, databases=databases, tables=tables, force=force, labels=labels)

    if msg:
        print(msg, file=sys.stderr, flush=True)
    print(name)


@command(name='restore')
@argument('name', metavar='BACKUP')
@option('-d', '--databases', type=List(regexp=r'\w+'), help='Comma-separated list of databases to restore.')
@option('--schema-only', is_flag=True, help='Restore only databases schemas')
def restore_command(ctx: Context, ch_backup: ClickhouseBackup, name: str, databases: list, schema_only: bool) -> None:
    """Restore data from a particular backup."""
    name = _validate_name(ctx, ch_backup, name)

    ch_backup.restore(name, databases, schema_only)


@command(name='delete')
@argument('name', metavar='BACKUP')
def delete_command(ctx: Context, ch_backup: ClickhouseBackup, name: str) -> None:
    """Delete particular backup."""
    name = _validate_name(ctx, ch_backup, name)

    deleted_backup_name, msg = ch_backup.delete(name)

    if msg:
        print(msg, file=sys.stderr, flush=True)

    if deleted_backup_name:
        print(deleted_backup_name)


@command(name='purge')
def purge_command(_ctx: Context, ch_backup: ClickhouseBackup) -> None:
    """Purge outdated backups."""
    names, msg = ch_backup.purge()

    if msg:
        print(msg, file=sys.stderr, flush=True)

    print('\n'.join(names))


@command(name='version')
def version_command(_ctx: Context, _ch_backup: ClickhouseBackup) -> None:
    """Print ch-backup version."""
    print(get_version())


def _validate_name(ctx: Context, ch_backup: ClickhouseBackup, name: str) -> str:
    backups = ch_backup.list()

    if name == 'LAST':
        if not backups:
            ctx.fail('There are no backups.')
        return backups[0].name

    if name not in (b.name for b in backups):
        ctx.fail(f'No backups with name "{name}" were found.')

    return name
