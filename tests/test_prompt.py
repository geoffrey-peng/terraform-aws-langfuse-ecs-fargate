#!/usr/bin/env python3
"""
Langfuse Prompt 测试脚本

用法:
  export LANGFUSE_SECRET_KEY="sk-lf-..."
  export LANGFUSE_PUBLIC_KEY="pk-lf-..."
  export LANGFUSE_HOST="http://your-alb-dns.elb.amazonaws.com"
  python test_prompt.py
"""

import os
import sys
from langfuse import Langfuse
from langfuse.types import TraceContext

# --- 从环境变量读取密钥 ---
SECRET_KEY = os.getenv("LANGFUSE_SECRET_KEY")
PUBLIC_KEY = os.getenv("LANGFUSE_PUBLIC_KEY")
HOST = os.getenv("LANGFUSE_HOST")

if not all([SECRET_KEY, PUBLIC_KEY, HOST]):
    print("错误: 请设置以下环境变量:")
    print("  LANGFUSE_SECRET_KEY")
    print("  LANGFUSE_PUBLIC_KEY")
    print("  LANGFUSE_HOST")
    sys.exit(1)

langfuse = Langfuse(
    secret_key=SECRET_KEY,
    public_key=PUBLIC_KEY,
    host=HOST,
)

prompt_name = "test-translator"
print("=== Langfuse Prompt Test ===")
print()

# 1. Create a prompt
print("[1/3] Creating prompt...")
try:
    langfuse.create_prompt(
        name=prompt_name,
        prompt="Translate the following text from {{from_lang}} to {{to_lang}}:\n\n{{text}}",
        config={"model": "gpt-4o", "temperature": 0.3},
        labels=["production"],
        tags=["translator"],
    )
    print(f"  Created: {prompt_name} (label: production)")
except Exception as e:
    print(f"  Already exists or error: {e}")

# 2. Fetch and use the prompt
print()
print("[2/3] Fetching & using prompt...")
prompt = langfuse.get_prompt(prompt_name, label="production")
compiled = prompt.compile(
    from_lang="English",
    to_lang="Chinese",
    text="Hello, how are you doing today?",
)
print(f"  Compiled prompt:")
for line in compiled.strip().split("\n"):
    print(f"    {line}")
print(f"  Config: {prompt.config}")

# 3. Trace an LLM call using this prompt
print()
print("[3/3] Tracing LLM call with prompt...")
ctx = TraceContext(trace_id=langfuse.create_trace_id())

gen = langfuse.start_observation(
    name="prompt-test-call",
    trace_context=ctx,
    as_type="generation",
    model="gpt-4o",
    prompt=prompt,
    input={"from_lang": "English", "to_lang": "Chinese", "text": "Hello, how are you doing today?"},
)
gen.update(output="\u4f60\u597d\uff0c\u4f60\u4eca\u5929\u600e\u4e48\u6837\uff1f", usage_details={"input": 15, "output": 5, "total": 20})
gen.end()
print(f"  Trace ID : {gen.trace_id}")
print(f"  Output   : \u4f60\u597d\uff0c\u4f60\u4eca\u5929\u600e\u4e48\u6837\uff1f")

langfuse.flush()
print()
print("=== Done! Check UI: Prompts tab & Traces ===")
