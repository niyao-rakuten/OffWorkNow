# OpenRouter SSE 请求组件

组件位于 `Sources/WorkdayCore/OpenRouter`，使用 Foundation，无第三方依赖，支持项目的 iOS 16+ / macOS 13+。暂未接入业务，也不会主动发送请求。

参考官方文档：
- [Quickstart](https://openrouter.ai/docs/quickstart#using-the-openrouter-api)
- [Streaming](https://openrouter.ai/docs/api_reference/streaming)

## 基础用法

```swift
import WorkdayCore

let client = OpenRouterClient(configuration: .init(
    apiKey: apiKey, // 由调用方提供，不在组件内保存
    appTitle: "WorkdayBuddy"
))
let request = OpenRouterRequest(
    model: selectedModelID, // OpenRouter 模型 slug
    messages: [
        .init(role: .system, content: "请简洁回答。"),
        .init(role: .user, content: "帮我规划今天的工作。")
    ],
    temperature: 0.7,
    maxTokens: 1024
)

let generationTask = Task {
    do {
        for try await chunk in client.stream(request) {
            // 各 choice 独立处理；不要把不同 choice 的内容合并。
            for choice in chunk.choices where choice.index == 0 {
                if let text = choice.delta?.content {
                    // 在 UI 调用方通过 MainActor 更新显示。
                    print(text, terminator: "")
                }
            }
            if let usage = chunk.usage {
                print(usage)
            }
        }
    } catch is CancellationError {
        // 用户取消。
    } catch {
        // 网络、HTTP、SSE 和模型错误交由调用方展示。
        print(error)
    }
}

// 用户停止生成，或宿主生命周期结束时：
generationTask.cancel()
```

返回 `AsyncThrowingStream<OpenRouterChunk, Error>`；每次调用创建独立 URLSession，流正常结束、失败或取消时关闭连接。创建 stream 会立即开始请求，应及时消费。消费 Task 在等待下一条数据时被取消会关闭连接。若主动 `break`，应释放 stream 和 iterator；不要保留已放弃的流。默认队列保留所有增量，调用方应快速消费，避免慢消费者积压内存。

遵循 Swift AsyncThrowingStream 的取消语义，消费任务取消时循环也可能正常退出；需要区分取消和成功时，在循环之后检查 `Task.isCancelled`。

## 参数扩展

常用参数为类型明确的 Swift 属性，其他参数通过可 Codable、Sendable 的 `OpenRouterJSON` 传入：

```swift
let request = OpenRouterRequest(
    model: selectedModelID,
    messages: [.init(role: .user, content: "你好")],
    additionalParameters: [
        "reasoning": .object(["effort": .string("low")]),
        "provider": .object(["allow_fallbacks": .bool(true)]),
        "response_format": .object(["type": .string("json_object")])
    ]
)
```

参数是否支持由所选模型决定。`model`、`messages`、`temperature`、`max_tokens` 由显式属性控制；`stream` 强制为 `true`，扩展参数无法覆盖这些字段。多模态消息通过 `.init(role:content:additionalFields:)` 传 JSON 数组；工具消息可通过 `additionalFields` 传入 `tool_call_id` / `tool_calls`。

响应暴露 `delta.content`、`delta.reasoning`、`delta.toolCalls` 和 `finishReason`。工具调用的 arguments 可能分多次到达，应由业务按 choice index 和 tool index 累积后解析。`usage` 及 `raw` 保留完整 JSON，便于未来扩展。组件不自动执行工具、不自动拼接对话、不自动重试。

## 协议与错误

- 请求为 POST `/api/v1/chat/completions`，Bearer 鉴权，Accept 为 `text/event-stream`。
- 支持 LF、CRLF、CR、UTF-8 BOM、中文跨分包、多行 `data:`；忽略心跳注释及其他 SSE 字段。
- `[DONE]` 才表示完整结束；提前断流抛出 `incompleteStream`，即使已收到 `finish_reason`。
- 末尾 usage chunk 继续传递；重复的 `finish_reason` 不会触发提前结束。
- 非 2xx 抛出 `.http(statusCode:body:)`；200 中的 `error` 事件抛出 `.api(code:message:)`，code 保留数字或字符串形式。
- 非 SSE Content-Type、非法 JSON / UTF-8、超大事件分别抛出明确错误。网络错误保留 URLSession 原始错误。
- 默认单事件和 HTTP 错误正文上限为 1 MiB，可配置；timeout 默认 120 秒。

`endpoint`、归属信息（`HTTP-Referer` / `X-OpenRouter-Title`）、超时及事件上限均可配置。`sessionConfiguration` 可注入 URLProtocol、代理等网络配置；传入后不要并发修改该配置。API Key 由调用方管理，组件不会记录请求或持久化凭据。

## 验证

### 终端真实调用

Swift 命令行 target `OpenRouterDebug` 直接依赖 WorkdayCore，调用同一个 `OpenRouterClient.stream`，没有另写网络实现。在 zsh 中执行：

```zsh
read -rs "OPENROUTER_API_KEY?OpenRouter API Key: "
echo
export OPENROUTER_API_KEY
swift run openrouter-debug
```

提示后粘贴 Key。默认模型为 `openrouter/free`；也可以传入模型和提示词：

```sh
swift run openrouter-debug openai/gpt-4o-mini "请用一句中文介绍你自己。"
```

输出实际模型、流式文本、用量、chunk 数量和耗时；只有组件收到 `[DONE]` 后才报告完整结束，失败则以状态码 1 退出。Ctrl+C 结束命令。Key 只从环境变量读取。

### 自动测试

```sh
swift test --scratch-path build/openrouter-tests
```

`OpenRouterTests` 使用 URLProtocol 模拟网络，覆盖请求编码、字节级 SSE 分帧、扩展响应、HTTP 错误、流内错误、Content-Type、断流及消费取消。无需真实 Key，不产生模型费用。
