# frozen_string_literal: true

module Docs
  # The agent runtimes people actually use, and the exact way to point each one
  # at `bottrunk-mcp`. Every snippet is taken from that client's own docs (see
  # `docs_url`); when a client changes its format, fix it here and the /connect
  # page follows.
  McpClient = Data.define(:slug, :name, :kind, :summary, :label, :snippet, :note, :docs_url)

  McpClient::SEED = [
    McpClient.new(
      slug: "claude-code", name: "Claude Code", kind: "CLI", label: "Terminal",
      summary: "One command. `claude mcp list` shows it connected.",
      snippet: "claude mcp add bottrunk -- npx -y bottrunk-mcp",
      note: "Add `--scope user` to make it available in every project instead of just this one.",
      docs_url: "https://docs.claude.com/en/docs/claude-code/mcp"
    ),
    McpClient.new(
      slug: "claude-desktop", name: "Claude Desktop", kind: "Desktop app", label: "claude_desktop_config.json",
      summary: "Settings → Developer → Edit Config, then restart the app.",
      snippet: <<~JSON.strip,
        {
          "mcpServers": {
            "bottrunk": { "command": "npx", "args": ["-y", "bottrunk-mcp"] }
          }
        }
      JSON
      note: "macOS: `~/Library/Application Support/Claude/claude_desktop_config.json` · Windows: `%APPDATA%\\Claude\\claude_desktop_config.json`.",
      docs_url: "https://modelcontextprotocol.io/docs/develop/connect-local-servers"
    ),
    McpClient.new(
      slug: "cursor", name: "Cursor", kind: "Editor", label: "~/.cursor/mcp.json",
      summary: "Global in `~/.cursor/mcp.json`, or per project in `.cursor/mcp.json`.",
      snippet: <<~JSON.strip,
        {
          "mcpServers": {
            "bottrunk": { "command": "npx", "args": ["-y", "bottrunk-mcp"] }
          }
        }
      JSON
      note: "Settings → MCP shows the tools once the server starts.",
      docs_url: "https://cursor.com/docs/context/mcp"
    ),
    McpClient.new(
      slug: "vscode", name: "VS Code (GitHub Copilot)", kind: "Editor", label: ".vscode/mcp.json",
      summary: "The key here is `servers`, not `mcpServers`.",
      snippet: <<~JSON.strip,
        {
          "servers": {
            "bottrunk": { "type": "stdio", "command": "npx", "args": ["-y", "bottrunk-mcp"] }
          }
        }
      JSON
      note: "Or in one line: `code --add-mcp '{\"name\":\"bottrunk\",\"command\":\"npx\",\"args\":[\"-y\",\"bottrunk-mcp\"]}'`. Use it from Agent mode.",
      docs_url: "https://code.visualstudio.com/docs/copilot/chat/mcp-servers"
    ),
    McpClient.new(
      slug: "cline", name: "Cline", kind: "Editor extension", label: "~/.cline/mcp.json",
      summary: "MCP Servers panel → Configure, or the file directly.",
      snippet: <<~JSON.strip,
        {
          "mcpServers": {
            "bottrunk": {
              "command": "npx", "args": ["-y", "bottrunk-mcp"],
              "disabled": false, "autoApprove": []
            }
          }
        }
      JSON
      note: "Leave `autoApprove` empty so you see each paid call before it runs.",
      docs_url: "https://docs.cline.bot/mcp/configuring-mcp-servers"
    ),
    McpClient.new(
      slug: "windsurf", name: "Windsurf (Cascade)", kind: "Editor", label: "~/.codeium/windsurf/mcp_config.json",
      summary: "Cascade → MCP servers → Configure, then refresh.",
      snippet: <<~JSON.strip,
        {
          "mcpServers": {
            "bottrunk": { "command": "npx", "args": ["-y", "bottrunk-mcp"] }
          }
        }
      JSON
      note: "Windsurf reads the file on refresh; you do not need to restart the editor.",
      docs_url: "https://docs.windsurf.com/windsurf/cascade/mcp"
    ),
    McpClient.new(
      slug: "zed", name: "Zed", kind: "Editor", label: "settings.json",
      summary: "Settings → AI → MCP Servers → Add Local Server, or edit settings directly.",
      snippet: <<~JSON.strip,
        {
          "context_servers": {
            "bottrunk": { "command": "npx", "args": ["-y", "bottrunk-mcp"], "env": {} }
          }
        }
      JSON
      note: "Zed calls them context servers; open the file with `zed: open settings file`.",
      docs_url: "https://zed.dev/docs/ai/mcp"
    ),
    McpClient.new(
      slug: "openclaw", name: "OpenClaw", kind: "Personal agent", label: "Terminal",
      summary: "Add it once; the agent picks the tools up on its next run.",
      snippet: <<~SH.strip,
        openclaw mcp add bottrunk \\
          --command npx \\
          --arg -y \\
          --arg bottrunk-mcp

        openclaw mcp doctor bottrunk --probe
      SH
      note: "Or in the config file under `mcp.servers.bottrunk` with `transport: \"stdio\"` and `enabled: true`.",
      docs_url: "https://docs.openclaw.ai/tools/mcp"
    ),
    McpClient.new(
      slug: "hermes", name: "Hermes Agent", kind: "Personal agent", label: "~/.hermes/config.yaml",
      summary: "Add the server to the config, then `hermes chat` — tools are discovered at startup.",
      snippet: <<~YAML.strip,
        mcp_servers:
          bottrunk:
            command: "npx"
            args: ["-y", "bottrunk-mcp"]
            env:
              BOTTRUNK_MAX_PER_CALL: "10000"
      YAML
      note: "Hermes passes through only the env you list, so put your caps there.",
      docs_url: "https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp"
    ),
    McpClient.new(
      slug: "goose", name: "Goose", kind: "CLI agent", label: "Terminal",
      summary: "`goose configure` → Add Extension → Command-Line Extension.",
      snippet: <<~SH.strip,
        goose configure
        # Add Extension → Command-Line Extension
        #   name:    bottrunk
        #   command: npx -y bottrunk-mcp

        # or in ~/.config/goose/config.yaml:
        # extensions:
        #   bottrunk:
        #     name: BotTrunk
        #     cmd: npx
        #     args: [-y, bottrunk-mcp]
        #     type: stdio
        #     enabled: true
      SH
      note: "Goose spells the command `cmd` and the environment `envs`.",
      docs_url: "https://block.github.io/goose/docs/getting-started/using-extensions"
    ),
    McpClient.new(
      slug: "openai-agents", name: "OpenAI Agents SDK", kind: "Framework", label: "Python",
      summary: "Spawn the server as a stdio subprocess and hand it to the agent.",
      snippet: <<~PY.strip,
        from agents import Agent, Runner
        from agents.mcp import MCPServerStdio

        async with MCPServerStdio(
            name="BotTrunk",
            params={"command": "npx", "args": ["-y", "bottrunk-mcp"]},
        ) as server:
            agent = Agent(
                name="Buyer",
                instructions="Use BotTrunk when you need data or real-world work.",
                mcp_servers=[server],
            )
            result = await Runner.run(agent, "Scrape https://example.com/pricing to markdown.")
            print(result.final_output)
      PY
      note: "`pip install openai-agents`. The wallet lives on the machine running the SDK.",
      docs_url: "https://openai.github.io/openai-agents-python/mcp/"
    ),
    McpClient.new(
      slug: "langchain", name: "LangChain / LangGraph", kind: "Framework", label: "Python",
      summary: "Load the tools into any LangChain agent or LangGraph node.",
      snippet: <<~PY.strip,
        # pip install langchain-mcp-adapters
        from langchain_mcp_adapters.client import MultiServerMCPClient

        client = MultiServerMCPClient({
            "bottrunk": {
                "command": "npx",
                "args": ["-y", "bottrunk-mcp"],
                "transport": "stdio",
            }
        })
        tools = await client.get_tools()
      PY
      note: "There is a JavaScript build too: `@langchain/mcp-adapters`.",
      docs_url: "https://github.com/langchain-ai/langchain-mcp-adapters"
    )
  ].freeze

  class McpClient
    def self.all = SEED

    def self.find(slug) = SEED.find { |c| c.slug == slug }
  end
end
