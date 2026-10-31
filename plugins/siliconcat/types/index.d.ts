export type Ask = { id: string; since: string; text: string; yesNo: boolean }

declare module 'claude-code' {
  interface PluginState {
    'siliconcat': { asks: Ask[]; checkedAt: number; pressed: string[]; director: boolean }
  }
}
