# Bundled local model

Base model: Qwen/Qwen3.5-4B, Copyright 2026 Alibaba Cloud, Apache License 2.0.
Source: https://huggingface.co/Qwen/Qwen3.5-4B

4-bit MLX conversion: mlx-community/Qwen3.5-4B-4bit, revision
0e7ffd5c629ef7719d4cbc04069232580bfa9d9c.

General planning uses the base instruction model. The local `mac-ax-bootstrap-v0`
LoRA adapter is retained only for legacy research tools; it is not applied to the
general planner. The app does not merge or modify the base checkpoint.

The self-contained Python/MLX runtime retains its upstream license files under
`mac-control/_internal`. The base model license is included alongside this notice.

Memory text embeddings: BAAI/bge-small-en-v1.5, revision
5c38ec7c405ec4b44b94cc5a9bb96e735b38267a (MIT).
Source: https://huggingface.co/BAAI/bge-small-en-v1.5
Its model card and checksummed manifest are bundled beside the embedding weights.
ONNX Runtime 1.23.2 (MIT) and its third-party notices are included below.
