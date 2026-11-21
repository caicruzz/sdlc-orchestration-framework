// Solo AI Factory: context handoff support for the factory-build orchestrator.
//
// OpenCode V2 server plugin. Before every model request of a top-level session
// it measures context usage the way OpenCode's own auto-compaction does (the
// newest assistant message's token usage against the model's input window).
// While a factory build is active (a build-state.md with Status `active`):
//
// - at or above `handoff_at_percent` (config.md `## Build`, default 70) it adds
//   a system note asking the orchestrator to follow the skill's Context handoff
// - once the session has been compacted it adds a system note pointing back to
//   build-state.md, and asks the summary request to keep that pointer
// - with Status `handoff-pending` it tells a fresh session that a handoff is
//   waiting, so "resume the factory build" picks it up
//
// Notes are added to the outgoing request only; nothing is written to history.

import { Plugin } from "@opencode/plugin"
import { readdirSync, readFileSync } from "node:fs"
import path from "node:path"

type BuildState = { slug: string; file: string; status: string }

const DEFAULT_PERCENT = 70

function readBuildStates(root: string): BuildState[] {
  const projects = path.join(root, ".ai-factory", "projects")
  let slugs: string[]
  try {
    slugs = readdirSync(projects, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
  } catch {
    return []
  }
  const states: BuildState[] = []
  for (const slug of slugs) {
    const file = path.join(projects, slug, "build-state.md")
    try {
      const match = readFileSync(file, "utf8").match(/^\|\s*\*\*Status\*\*\s*\|\s*`?([a-z-]+)`?/im)
      if (match) states.push({ slug, file, status: match[1].toLowerCase() })
    } catch {
      // No state file for this slug.
    }
  }
  return states
}

function handoffPercent(root: string): number {
  try {
    const config = readFileSync(path.join(root, ".ai-factory", "config.md"), "utf8")
    const match = config.match(/^\|\s*\*\*handoff_at_percent\*\*\s*\|\s*(\d+(?:\.\d+)?)/im)
    const value = match ? Number(match[1]) : NaN
    if (value > 0 && value < 100) return value
  } catch {
    // Missing config: use the default.
  }
  return DEFAULT_PERCENT
}

export default Plugin.define({
  id: "factory-context",
  async setup(ctx) {
    const root = ctx.location.directory
    const topLevel = new Map<string, boolean>()

    const isTopLevel = async (sessionID: string) => {
      const known = topLevel.get(sessionID)
      if (known !== undefined) return known
      const session = await ctx.session.get({ sessionID })
      const result = !session.parentID
      topLevel.set(sessionID, result)
      return result
    }

    const inputWindow = async (ref: { id: string; providerID: string }) => {
      const listed: any = await ctx.model.list()
      const models: any[] = Array.isArray(listed) ? listed : (listed?.data ?? [])
      const model = models.find((item) => item.id === ref.id && item.providerID === ref.providerID)
      const limit = model?.limit
      if (!limit) return 0
      return limit.input && limit.context ? Math.min(limit.input, limit.context) : limit.input || limit.context || 0
    }

    await ctx.session.hook("context", async (event) => {
      try {
        const states = readBuildStates(root)
        if (states.length === 0) return
        if (!(await isTopLevel(event.sessionID))) return

        const pending = states.filter((state) => state.status === "handoff-pending")
        const active = states.filter((state) => state.status === "active")
        const messages: any[] = [...(await ctx.session.context({ sessionID: event.sessionID }))]

        // A fresh session (no assistant reply yet) with a handoff waiting.
        if (pending.length > 0 && !messages.some((message) => message.type === "assistant")) {
          const list = pending.map((state) => `${state.slug} (${state.file})`).join(", ")
          event.system.push({
            type: "text",
            text: `Solo AI Factory: a factory-build handoff is pending for ${list}. If the user asks to resume the build, invoke the factory-build skill and follow its Resume section.`,
          })
          return
        }
        if (active.length === 0) return

        const files = active.map((state) => state.file).join(", ")

        if (messages.some((message) => message.type === "compaction")) {
          event.system.push({
            type: "text",
            text: `Solo AI Factory: this conversation was compacted during a factory build. Before any further build action, re-read ${files} and every task file, trust them over the summary, and follow the factory-build Context handoff section.`,
          })
        }

        const anchor = messages.findLast((message) => message.type === "assistant" && message.tokens)
        if (!anchor) return
        const window = await inputWindow(event.model)
        if (window <= 0) return
        const tokens = anchor.tokens
        const used = tokens.input + tokens.cache.read + tokens.cache.write + tokens.output + tokens.reasoning
        const percent = Math.round((used / window) * 100)
        const threshold = handoffPercent(root)
        if (percent < threshold) return
        event.system.push({
          type: "text",
          text: `Solo AI Factory: context usage is ${percent}% (handoff_at_percent is ${threshold}). Follow the factory-build Context handoff section now: finish the steps in flight, update ${files}, and ask the user to start a fresh session.`,
        })
      } catch (error) {
        // Never break the session over a missing file or an API change.
        console.error("factory-context:", error)
      }
    })

    await ctx.session.hook("compaction", async (event) => {
      try {
        if (!(await isTopLevel(event.sessionID))) return
        const active = readBuildStates(root).filter((state) => state.status === "active")
        if (active.length === 0) return
        event.system.push({
          type: "text",
          text: `A Solo AI Factory build is in progress. The summary must say that the build state is in ${active
            .map((state) => state.file)
            .join(", ")}, that task status lives in the task files, and that both must be re-read before any further build action.`,
        })
      } catch (error) {
        console.error("factory-context:", error)
      }
    })
  },
})
