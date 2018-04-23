# -*- coding: utf-8 -*-
"""
Command-line interface.
"""

import logging
import re
import sys
from functools import wraps

from click import (Choice, ParamType, Path, argument, group, option,
                   pass_context)

from .backup import ClickhouseBackup
from .config import Config
from .util import drop_privileges, setup_environment, setup_logging


@group(context_settings=dict(help_option_names=['-h', '--help']))
@option(
    '-c',
    '--config',
    type=Path(exists=True),
    default='/etc/yandex/ch-backup/ch-backup.conf',
    help='Configuration file path.')
@option(
    '--protocol',
    type=Choice(['http', 'https']),
    help='Protocol used to connect to ClickHouse server.')
@option('--port', type=int, help='Port used to connect to ClickHouse server.')
@option(
    '--ca-path',
    type=str,
    help='Path to custom CA bundle path for https protocol.')
@option(
    '--insecure',
    is_flag=True,
    help='Disable certificate verification for https protocol.')
@pass_context
def cli(ctx, config, protocol, port, ca_path, insecure):
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

    setup_logging(cfg['logging'])
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
                logging.info('Executing command \'%s\', params: %s, args %s',
                             ctx.command.name, {
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
            msg = '\'%s\' is not a valid list of items' % value
            if self.regexp:
                msg += ' matching the format: %s' % self.regexp_str

            self.fail(msg, param, ctx)


@command(name='list')
def list_command(_ctx, ch_backup):
    """List existing backups."""
    backups = ch_backup.list()

    print('\n'.join(sorted(backups, reverse=True)))


@command()
@argument('name', metavar='BACKUP')
def show(ctx, ch_backup, name):
    """Show details for a particular backup."""
    name = _validate_name(ctx, ch_backup, name)

    print(ch_backup.get(name))


@command()
@option(
    '-d',
    '--databases',
    type=List(regexp=r'\w+'),
    help='Comma-separated list of databases to backup.')
@option(
    '-f',
    '--force',
    is_flag=True,
    help='Enables force mode (backup.min_interval is ignored).')
def backup(_ctx, ch_backup, databases, force):
    """Perform backup."""
    (name, msg) = ch_backup.backup(databases, force)
    if msg:
        print(msg, file=sys.stderr, flush=True)
    print(name)


@command()
@argument('name', metavar='BACKUP')
@option(
    '-d',
    '--databases',
    type=List(regexp=r'\w+'),
    help='Comma-separated list of databases to restore.')
@option('--schema-only', is_flag=True, help='Restore only databases schemas')
def restore(ctx, ch_backup, name, databases, schema_only):
    """Restore data from a particular backup."""
    name = _validate_name(ctx, ch_backup, name)

    ch_backup.restore(name, databases, schema_only)


def _validate_name(ctx, ch_backup, name):

    backups = ch_backup.list()

    if name == 'LAST':
        if not backups:
            ctx.fail('There are no backups.')
        return max(backups)

    if name not in backups:
        ctx.fail('No backups with name "%s" were found.' % name)

    return name
