# Bundled local model

Base model: Qwen/Qwen3.5-4B, Copyright 2026 Alibaba Cloud, Apache License 2.0.
Source: https://huggingface.co/Qwen/Qwen3.5-4B

4-bit MLX conversion: mlx-community/Qwen3.5-4B-4bit, revision
0e7ffd5c629ef7719d4cbc04069232580bfa9d9c.

The base is used with the local `mac-ax-bootstrap-v0` LoRA adapter from
`llm-research`. This adapter specializes next-action selection on accessibility
text. The app does not merge or modify the base checkpoint. Research runtime
rules can refine the model's proposal.

The self-contained Python/MLX runtime retains its upstream license files under
`mac-control/_internal`. The base model license is included alongside this notice.
