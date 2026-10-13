"""No weights, network, or GPU are needed for these runtime checks."""
import importlib
import os
import subprocess

import numpy as np
import torch
import torchaudio


def test_runtime_imports():
    for name in (
        "breeze_infer.api", "qwen_tts", "onnxruntime", "librosa",
        "soundfile", "accelerate", "transformers", "sox", "gradio",
    ):
        importlib.import_module(name)


def test_cpu_audio_and_bfloat16():
    assert torch.version.cuda == "13.0"
    # Inspect compiled targets without initializing CUDA or requiring a GPU.
    assert "sm_120" in torch._C._cuda_getArchFlags().split()
    audio = torchaudio.functional.resample(torch.zeros(1, 240), 24000, 16000)
    assert audio.shape == (1, 160)
    assert (torch.ones(2, 2, dtype=torch.bfloat16) @ torch.ones(2, 2, dtype=torch.bfloat16)).shape == (2, 2)
    from breeze_infer.api import _pcm16
    assert _pcm16(np.array([-1, 0, 1])) == b"\x01\x80\x00\x00\xff\x7f"


def test_dependency_metadata_only_known_mismatch():
    result = subprocess.run(["python", "-m", "pip", "check"], capture_output=True, text=True, check=False)
    # Deliberate inherited exception; any additional broken dependency fails CI.
    assert result.returncode == 1
    assert result.stdout.strip() == (
        "torchaudio 2.11.0+cu130 has requirement torch==2.11.0, but you have torch 2.13.0+cu130."
    )


def test_nonroot_writable_caches():
    assert os.getuid() == 1000
    for key in ("HOME", "HF_HOME", "NUMBA_CACHE_DIR"):
        assert os.access(os.environ[key], os.W_OK)
