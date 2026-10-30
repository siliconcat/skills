export type Ask = { id: string; since: string; text: string }

declare module 'claude-code' {
  interface PluginState {
    'director': { asks: Ask[]; checkedAt: number }
  }
}
