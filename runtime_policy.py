"""Keep CUDA eager operators on precompiled ATen kernels, without runtime JIT.

Loaded by PyTorch's documented TORCH_PYTHON_NATIVE_USER_GRAPH_ORDER_FN hook.
Only the optional Python-native CUDA overrides are removed; CPU registrations
and upstream model/attention configuration are unchanged.
"""


def aten_cuda_only(op_symbol, dispatch_key, nodes):
    return [] if dispatch_key == "CUDA" else nodes
