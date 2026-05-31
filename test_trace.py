#!/usr/bin/env python3
"""
Langfuse Trace 测试脚本

用法:
  export LANGFUSE_SECRET_KEY="sk-lf-..."
  export LANGFUSE_PUBLIC_KEY="pk-lf-..."
  export LANGFUSE_HOST="http://your-alb-dns.elb.amazonaws.com"
  python test_trace.py
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

print("=== Langfuse Trace Test ===")

# 1. Create span (creates trace)
obs = langfuse.start_observation(name="hello-world", input="Hi!")
trace_id = obs.trace_id
obs.end()
print(f"  Trace ID : {trace_id}")
print(f"  Span     : hello-world (OK)")

# 2. Create generation
ctx = TraceContext(trace_id=trace_id)
gen = langfuse.start_observation(
    name="gpt-4o-completion",
    trace_context=ctx,
    as_type="generation",
    model="gpt-4o",
    input="1+1=?",
)
gen.update(output="2", usage_details={"input": 10, "output": 1, "total": 11})
gen.end()
print(f"  Gen      : gpt-4o-completion -> '2' (OK)")

# 3. Score
langfuse.create_score(trace_id=trace_id, name="quality", value=9.5, comment="Great!")
print(f"  Score    : quality=9.5 (OK)")

langfuse.flush()
print("")
print("=== Done! Refresh the Langfuse UI ===")
