#!/bin/bash
# ============================================================
# Langfuse Trace 测试脚本 (curl)
#
# 用法:
#   export LANGFUSE_SECRET_KEY="sk-lf-..."
#   export LANGFUSE_PUBLIC_KEY="pk-lf-..."
#   export LANGFUSE_HOST="http://your-alb-dns.elb.amazonaws.com"
#   bash test_trace.sh
# ============================================================
set -e

# --- 从环境变量读取 ---
if [ -z "$LANGFUSE_SECRET_KEY" ] || [ -z "$LANGFUSE_PUBLIC_KEY" ] || [ -z "$LANGFUSE_HOST" ]; then
    echo "错误: 请设置以下环境变量:"
    echo "  LANGFUSE_SECRET_KEY"
    echo "  LANGFUSE_PUBLIC_KEY"
    echo "  LANGFUSE_HOST"
    exit 1
fi

SECRET_KEY="$LANGFUSE_SECRET_KEY"
PUBLIC_KEY="$LANGFUSE_PUBLIC_KEY"
BASE_URL="$LANGFUSE_HOST"
TRACE_ID="test-trace-$(date +%s)"

echo "============================================"
echo "Langfuse Trace 测试"
echo "Base URL: $BASE_URL"
echo "Trace ID: $TRACE_ID"
echo "============================================"

# 1. 创建 Trace
echo ""
echo "[1/3] 创建 Trace..."
TRACE_RESP=$(curl -s -w "\n%{http_code}" \
  -X POST "${BASE_URL}/api/public/ingestion" \
  -H "Authorization: Basic $(echo -n "${PUBLIC_KEY}:${SECRET_KEY}" | base64)" \
  -H "Content-Type: application/json" \
  -d "{
    \"batch\": [
      {
        \"id\": \"${TRACE_ID}\",
        \"type\": \"trace-create\",
        \"body\": {
          \"name\": \"test-curl-trace\",
          \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
          \"userId\": \"test-user\",
          \"metadata\": {
            \"source\": \"curl-tester\",
            \"env\": \"test\"
          },
          \"tags\": [\"test\", \"curl\", \"first-trace\"]
        }
      }
    ]
  }")

HTTP_CODE=$(echo "$TRACE_RESP" | tail -1)
TRACE_BODY=$(echo "$TRACE_RESP" | sed '$d')
echo "  HTTP Status: $HTTP_CODE"
echo "  Response: $TRACE_BODY"

# 2. 创建 Span (Observation)
echo ""
echo "[2/3] 创建 Span..."
SPAN_ID="test-span-$(date +%s)"
SPAN_RESP=$(curl -s -w "\n%{http_code}" \
  -X POST "${BASE_URL}/api/public/ingestion" \
  -H "Authorization: Basic $(echo -n "${PUBLIC_KEY}:${SECRET_KEY}" | base64)" \
  -H "Content-Type: application/json" \
  -d "{
    \"batch\": [
      {
        \"id\": \"${SPAN_ID}\",
        \"type\": \"observation-create\",
        \"body\": {
          \"name\": \"test-llm-call\",
          \"traceId\": \"${TRACE_ID}\",
          \"type\": \"GENERATION\",
          \"startTime\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
          \"endTime\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
          \"model\": \"gpt-4o\",
          \"input\": \"Hello, are you there?\",
          \"output\": \"Yes, I am here!\",
          \"usage\": {
            \"input\": 5,
            \"output\": 5,
            \"total\": 10
          },
          \"usageDetails\": {
            \"input\": 5,
            \"output\": 5
          }
        }
      }
    ]
  }")

HTTP_CODE=$(echo "$SPAN_RESP" | tail -1)
SPAN_BODY=$(echo "$SPAN_RESP" | sed '$d')
echo "  HTTP Status: $HTTP_CODE"
echo "  Response: $SPAN_BODY"

# 3. 创建 Score
echo ""
echo "[3/3] 创建 Score..."
SCORE_RESP=$(curl -s -w "\n%{http_code}" \
  -X POST "${BASE_URL}/api/public/ingestion" \
  -H "Authorization: Basic $(echo -n "${PUBLIC_KEY}:${SECRET_KEY}" | base64)" \
  -H "Content-Type: application/json" \
  -d "{
    \"batch\": [
      {
        \"id\": \"test-score-$(date +%s)\",
        \"type\": \"score-create\",
        \"body\": {
          \"name\": \"quality\",
          \"value\": 0.95,
          \"traceId\": \"${TRACE_ID}\",
          \"comment\": \"Auto-generated test score\"
        }
      }
    ]
  }")

HTTP_CODE=$(echo "$SCORE_RESP" | tail -1)
SCORE_BODY=$(echo "$SCORE_RESP" | sed '$d')
echo "  HTTP Status: $HTTP_CODE"
echo "  Response: $SCORE_BODY"

echo ""
echo "============================================"
echo "测试完成!"
echo "打开浏览器查看 Trace:"
echo "  ${BASE_URL}/project/<project-id>/traces/${TRACE_ID}"
echo ""
echo "或者直接查看所有 Traces:"
echo "  ${BASE_URL}"
echo "============================================"
