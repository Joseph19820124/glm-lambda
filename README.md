# GLM Lambda API

基于 AWS Lambda 和智谱 GLM 的无服务器聊天 API，支持多轮对话和会话管理。

## 在线演示

- **聊天界面**: https://joseph19820124.github.io/glm-lambda/chat.html
- **API 文档**: https://joseph19820124.github.io/glm-lambda/

## 架构图

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              用户浏览器                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                     静态页面 (GitHub Pages)                             │  │
│  │                     HTML / CSS / JavaScript                            │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ HTTPS (fetch API)
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                        │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    Lambda Function (glm-chat)                        │    │
│  │  ┌─────────────────────────────────────────────────────────────┐    │    │
│  │  │  lambda_handler()                                            │    │    │
│  │  │                                                              │    │    │
│  │  │  1. 解析请求参数                                              │    │    │
│  │  │  2. 从 DynamoDB 获取对话历史                                  │    │    │
│  │  │  3. 构建 messages 数组                                        │    │    │
│  │  │  4. 调用 GLM API                                              │    │    │
│  │  │  5. 保存对话到 DynamoDB                                       │    │    │
│  │  │  6. 返回 AI 回复                                              │    │    │
│  │  └─────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│           │                                              │                   │
│           │ Query/PutItem                                │ HTTPS POST        │
│           ▼                                              ▼                   │
│  ┌─────────────────────┐                    ┌─────────────────────────┐     │
│  │     DynamoDB        │                    │      Z.AI (GLM API)     │     │
│  │ ┌─────────────────┐ │                    │                         │     │
│  │ │ glm-conversations│ │                    │  api.z.ai/api/paas/v4  │     │
│  │ │                 │ │                    │                         │     │
│  │ │ • session_id    │ │                    │  Models:                │     │
│  │ │ • timestamp     │ │                    │  • glm-4.7-flash        │     │
│  │ │ • user_message  │ │                    │  • glm-4.7              │     │
│  │ │ • assistant_msg │ │                    │  • glm-4.6              │     │
│  │ │ • ttl (7 days)  │ │                    │                         │     │
│  │ └─────────────────┘ │                    └─────────────────────────┘     │
│  └─────────────────────┘                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 数据流

```
用户输入 ──► 前端 JavaScript ──► Lambda Function ──► GLM API
                                      │
                                      ▼
                                  DynamoDB
                                (保存对话历史)
                                      │
                                      ▼
用户看到回复 ◄── 前端渲染 ◄── Lambda 返回 ◄── GLM 返回
```

## 技术栈

| 组件 | 技术 | 说明 |
|------|------|------|
| 前端 | HTML/CSS/JS | 静态页面，托管在 GitHub Pages |
| 后端 | AWS Lambda (Python 3.11) | 无服务器函数，按需执行 |
| 数据库 | DynamoDB | NoSQL，自动扩展，TTL 自动清理 |
| AI 模型 | GLM-4.7-flash | 智谱 AI 大语言模型 |
| API 网关 | Lambda Function URL | 免费的 HTTPS 端点 |

## API 使用

### 请求

```bash
curl -X POST https://kjkwvmbpiaxnzdnehfyjxcuela0twmre.lambda-url.us-east-1.on.aws/ \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "你好",
    "session_id": "user001",
    "model": "glm-4.7-flash"
  }'
```

### 响应

```json
{
  "reply": "你好！有什么我可以帮助你的吗？",
  "session_id": "user001",
  "model": "glm-4.7-flash",
  "usage": {
    "prompt_tokens": 17,
    "completion_tokens": 20,
    "total_tokens": 37
  }
}
```

## 部署

```bash
# 1. 配置 AWS CLI
aws configure

# 2. 修改 deploy.sh 中的 ZHIPU_API_KEY
vim deploy.sh

# 3. 执行部署
chmod +x deploy.sh
./deploy.sh
```

## 项目结构

```
glm-lambda/
├── lambda_function.py    # Lambda 函数代码
├── deploy.sh             # 部署脚本
├── docs/
│   ├── index.html        # API 文档页面
│   └── chat.html         # 聊天界面
└── README.md
```

## 成本估算

| 服务 | 免费额度 | 超出后价格 |
|------|---------|-----------|
| Lambda | 100万次/月 | $0.20/百万次 |
| DynamoDB | 25GB 存储 | $0.25/GB |
| GLM API | 按 token 计费 | 约 ¥0.001/千 token |

对于个人使用，基本在免费额度内。

## License

MIT
