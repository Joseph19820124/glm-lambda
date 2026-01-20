import json
import urllib.request
import os
import boto3
import time
import uuid

# 初始化 DynamoDB
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE', 'glm-conversations'))

def get_conversation_history(session_id, limit=10):
    """获取对话历史"""
    try:
        response = table.query(
            KeyConditionExpression='session_id = :sid',
            ExpressionAttributeValues={':sid': session_id},
            ScanIndexForward=False,
            Limit=limit
        )
        items = response.get('Items', [])
        items.reverse()

        messages = []
        for item in items:
            messages.append({'role': 'user', 'content': item['user_message']})
            messages.append({'role': 'assistant', 'content': item['assistant_message']})
        return messages
    except Exception as e:
        print(f"Error getting history: {e}")
        return []

def save_conversation(session_id, user_message, assistant_message):
    """保存对话记录"""
    try:
        table.put_item(Item={
            'session_id': session_id,
            'timestamp': int(time.time() * 1000),
            'message_id': str(uuid.uuid4()),
            'user_message': user_message,
            'assistant_message': assistant_message,
            'ttl': int(time.time()) + 86400 * 7
        })
    except Exception as e:
        print(f"Error saving conversation: {e}")

def call_glm_api(messages, model, api_key):
    """调用 GLM API"""
    url = os.environ.get('GLM_API_URL', 'https://api.z.ai/api/paas/v4/chat/completions')

    payload = {
        'model': model,
        'messages': messages,
        'max_tokens': 2048,
        'temperature': 0.7
    }

    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json'
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers=headers,
        method='POST'
    )

    with urllib.request.urlopen(req, timeout=240) as response:
        return json.loads(response.read().decode('utf-8'))

def lambda_handler(event, context):
    """Lambda 入口函数"""

    api_key = os.environ.get('ZHIPU_API_KEY')
    if not api_key:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'ZHIPU_API_KEY not configured'})
        }

    if 'body' in event:
        body = json.loads(event.get('body', '{}'))
    else:
        body = event

    user_message = body.get('message', '你好')
    default_model = os.environ.get('DEFAULT_MODEL', 'glm-4.7-flash')
    model = body.get('model', default_model)
    session_id = body.get('session_id', 'default')
    new_session = body.get('new_session', False)

    try:
        messages = [{'role': 'system', 'content': '你是一个有帮助的AI助手。'}]

        if not new_session:
            history = get_conversation_history(session_id)
            messages.extend(history)

        messages.append({'role': 'user', 'content': user_message})

        result = call_glm_api(messages, model, api_key)
        assistant_message = result['choices'][0]['message']['content']

        save_conversation(session_id, user_message, assistant_message)

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'reply': assistant_message,
                'session_id': session_id,
                'model': model,
                'usage': result.get('usage', {})
            }, ensure_ascii=False)
        }

    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        return {
            'statusCode': e.code,
            'body': json.dumps({'error': f'GLM API error: {error_body}'})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
