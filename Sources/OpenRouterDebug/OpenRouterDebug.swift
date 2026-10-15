import Foundation
import WorkdayCore

@main
struct OpenRouterDebug {
    static func main() async {
        setbuf(stdout, nil)
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") {
            print("OPENROUTER_API_KEY=… swift run openrouter-debug [model] [prompt]")
            return
        }
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("请先设置 OPENROUTER_API_KEY 环境变量。")
        }
        let model = arguments.first ?? "openrouter/free"
        let prompt = arguments.count > 1 ? arguments.dropFirst().joined(separator: " ") : "请用一句中文介绍你自己。"
        let client = OpenRouterClient(configuration: .init(apiKey: key, appTitle: "WorkdayBuddy Swift Debug"))
        let request = OpenRouterRequest(model: model, messages: [.init(role: .user, content: prompt)], maxTokens: 256)
        print("通过 OpenRouterClient 请求模型：\(model)\n")
        let started = Date()
        var count = 0
        var reportedModel = false
        do {
            for try await chunk in client.stream(request) {
                count += 1
                if !reportedModel, let resolvedModel = chunk.model {
                    print("实际模型：\(resolvedModel)\n")
                    reportedModel = true
                }
                for choice in chunk.choices where choice.index == 0 {
                    if let content = choice.delta?.content {
                        FileHandle.standardOutput.write(Data(content.utf8))
                    }
                }
                if let usage = chunk.usage {
                    let data = try JSONEncoder().encode(usage)
                    print("\n\n用量：\(String(decoding: data, as: UTF8.self))")
                }
            }
            try Task.checkCancellation()
            print(String(format: "\n[DONE] SSE 完整结束 · %d 个 chunk · %.2f 秒", count, Date().timeIntervalSince(started)))
        } catch {
            fail("请求失败：\(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
