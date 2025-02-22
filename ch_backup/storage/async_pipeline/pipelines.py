"""
Free functions that create and run pipelines. Can be started in multiprocessing pool.
"""
from pathlib import Path
from tarfile import BLOCKSIZE
from typing import Any, AnyStr, List, Sequence

from ch_backup.calculators import (calc_aligned_files_size, calc_encrypted_size, calc_tarball_size)
from ch_backup.encryption import get_encryption
from ch_backup.storage.async_pipeline.pipeline_builder import (PipelineBuilder, PypelnStage)
from ch_backup.util import exhaust_iterator


def upload_data_pipeline(config: dict, data: AnyStr, remote_path: str, encrypt: bool) -> None:
    """
    Entrypoint of upload data pipeline.
    """
    builder = PipelineBuilder(config)

    estimated_size = len(data)
    builder.build_iterable_stage([data])
    if encrypt:
        builder.build_encrypt_stage()
        estimated_size = _calc_encrypted_size(config, estimated_size)
    builder.build_uploading_stage(remote_path, estimated_size)

    run(builder.pipeline())


def upload_file_pipeline(config: dict, local_path: Path, remote_path: str, encrypt: bool, delete_after: bool) -> None:
    """
    Entrypoint of upload file pipeline.
    """
    builder = PipelineBuilder(config)

    estimated_size = calc_aligned_files_size([local_path])
    builder.build_read_file_stage(file_path=local_path)
    if encrypt:
        builder.build_encrypt_stage()
        estimated_size = _calc_encrypted_size(config, estimated_size)
    builder.build_uploading_stage(remote_path, estimated_size)
    if delete_after:
        builder.build_delete_files_stage([local_path])

    run(builder.pipeline())


def upload_files_tarball_pipeline(config: dict, base_path: Path, file_relative_paths: List[Path], remote_path: str,
                                  encrypt: bool, delete_after: bool) -> None:
    """
    Entrypoint of upload files tarball pipeline.
    """
    builder = PipelineBuilder(config)
    file_absolute_paths = [base_path / rel_path for rel_path in file_relative_paths]

    estimated_size = calc_aligned_files_size(file_absolute_paths, alignment=BLOCKSIZE)
    estimated_size = calc_tarball_size([str(f) for f in file_relative_paths], estimated_size)
    builder.build_read_files_tarball_stage(base_path, file_relative_paths)
    if encrypt:
        builder.build_encrypt_stage()
        estimated_size = _calc_encrypted_size(config, estimated_size)
    builder.build_uploading_stage(remote_path, estimated_size)
    if delete_after:
        builder.build_delete_files_stage(file_absolute_paths)

    run(builder.pipeline())


def download_data_pipeline(config: dict, remote_path: str, decrypt: bool) -> bytes:
    """
    Entrypoint of download data pipeline.
    """
    builder = PipelineBuilder(config)

    builder.build_download_storage_stage(remote_path)
    if decrypt:
        builder.build_decrypt_stage()
    builder.build_collect_data_stage()

    return run_and_return_first(builder.pipeline())


def download_file_pipeline(config: dict, remote_path: str, local_path: Path, decrypt: bool) -> None:
    """
    Entrypoint of download file pipeline.
    """
    builder = PipelineBuilder(config)

    builder.build_download_storage_stage(remote_path)
    if decrypt:
        builder.build_decrypt_stage()
    builder.build_write_file_stage(local_path)

    run(builder.pipeline())


def download_files_pipeline(config: dict, remote_path: str, local_path: Path, decrypt: bool) -> None:
    """
    Entrypoint of download files pipeline.
    """
    builder = PipelineBuilder(config)

    builder.build_download_storage_stage(remote_path)
    if decrypt:
        builder.build_decrypt_stage()
    builder.build_write_files_stage(local_path)

    run(builder.pipeline())


def delete_multiple_storage_pipeline(config: dict, remote_paths: Sequence[str]) -> None:
    """
    Entrypoint of delete multiple objects pipeline.
    """
    builder = PipelineBuilder(config)

    builder.build_delete_multiple_storage_stage(remote_paths)

    run(builder.pipeline())


def run(pipeline: PypelnStage) -> None:
    """
    Run pipeline until it is complete.
    """
    itr = iter(pipeline)
    exhaust_iterator(itr)


def run_and_return_first(pipeline: PypelnStage) -> Any:
    """
    Run pipeline until it is complete and return first its result.
    """
    itr = iter(pipeline)

    result = next(itr)  # Fetch and save first item
    exhaust_iterator(itr)

    return result


def _calc_encrypted_size(config: dict, data_size: int) -> int:
    enc_conf = config['encryption']
    chunk_size = enc_conf['chunk_size']
    metadata_size = get_encryption(enc_conf['type'], enc_conf).metadata_size()

    return calc_encrypted_size(data_size, chunk_size, metadata_size)
