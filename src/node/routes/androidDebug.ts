import { logger } from "@coder/logger"
import { Router, raw } from "express"
import { promises as fs } from "fs"
import * as path from "path"

/**
 * Debug logging endpoint for the Android/mobile builds (VS Server Android).
 *
 * When `CS_DEBUG_LOG_DIR` is set (see scripts/termux-start.sh debug), the
 * workbench's mobile debug contribution probes `/-/android-debug/ping` and, if
 * present, streams browser-side console errors, window errors, unhandled
 * rejections and keyboard/input traces to `client.log` in that directory.
 *
 * Server output is captured separately (tee'd into server.log by the launcher)
 * and the VS Code workbench logs are copied in at shutdown.
 */
export const isEnabled = (): boolean => !!process.env.CS_DEBUG_LOG_DIR

const logDir = (): string => process.env.CS_DEBUG_LOG_DIR as string
const clientLog = (): string => path.join(logDir(), "client.log")

export const router = Router()

router.get("/ping", (_, res) => {
  res.json({ ok: true, dir: logDir() })
})

// Accept anything: the client posts JSON, but we want to be robust against
// sendBeacon/text payloads as well. The global express.json() (registered
// earlier) handles application/json; this catches the rest.
router.post("/log", raw({ type: () => true, limit: "1024kb" }), async (req, res) => {
  try {
    const body = req.body
    const line =
      body === undefined || body === null
        ? ""
        : typeof body === "string"
          ? body
          : Buffer.isBuffer(body)
            ? body.toString("utf8")
            : JSON.stringify(body)
    if (line) {
      await fs.appendFile(clientLog(), line + "\n")
    }
  } catch (error) {
    logger.warn(`android-debug: failed to write client log: ${error}`)
  }
  res.status(204).end()
})
