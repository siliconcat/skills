export type Ask = { id: string; since: string; text: string }

declare module 'claude-code' {
  interface PluginState {
    'siliconcat': { asks: Ask[]; checkedAt: number }
  }
}
