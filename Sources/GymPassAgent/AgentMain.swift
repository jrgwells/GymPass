import Foundation
import GymPassAgentCore

@main
struct GymPassAgentMain {
    static func main() async {
        await AgentService.run()
    }
}
