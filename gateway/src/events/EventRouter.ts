import type { EventFrame } from "../protocol";

type FrameCallback = (frame: EventFrame) => void;

/** Routes event frames to subscribed callbacks (one per session key). */
export class EventRouter {
  private subscriptions = new Map<string, Set<FrameCallback>>();

  subscribe(sessionKey: string, callback: FrameCallback): () => void {
    let subs = this.subscriptions.get(sessionKey);
    if (!subs) {
      subs = new Set();
      this.subscriptions.set(sessionKey, subs);
    }
    subs.add(callback);
    return () => {
      subs!.delete(callback);
      if (subs!.size === 0) this.subscriptions.delete(sessionKey);
    };
  }

  publish(frame: EventFrame): void {
    const subs = this.subscriptions.get(frame.sessionKey);
    if (!subs) return;
    for (const cb of subs) {
      try { cb(frame); } catch (err) {
        console.error("[router] Callback error:", err);
      }
    }
  }
}
