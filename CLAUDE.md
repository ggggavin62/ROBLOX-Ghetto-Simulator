# ROBLOX PROJECT: URBAN FPS BATTLEGROUNDS

## 1. Core Tech & Style
- **Engine:** Roblox Luau. Use strict typing (`--!strict`) on all scripts.
- **Avatar:** R15.
- **Perspective:** First-Person ONLY. `StarterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson`.
- **Map Loading:** Assume `Workspace.StreamingEnabled = true`. Scripts must account for parts not being loaded immediately (use `WaitForChild`).

## 2. Game Architecture
- **Framework:** Use Rojo structure (`src/server`, `src/client`, `src/shared`).
- **Weapon System:** Weapons are Raycast-based (not physical projectiles). Use `workspace:Raycast()`. Damage is handled on the SERVER via `RemoteEvents` after client registers a hit.
- **Security:** NEVER trust the client. Server must verify raycast distances and line-of-sight before applying damage to prevent exploiters.

## 3. The "Backfill" AI System
- **Player Target:** The server must always have exactly 25 entities (Players + NPCs).
- **Logic:** Create a `ServerScriptService/AISpawner.luau` script. It must check the player count. If Players < 25, spawn NPCs to make the total 25.
- **NPC Despawn:** Bind to `Players.PlayerAdded`. When a real player joins, instantly `:Destroy()` one NPC.
- **AI AI Pathfinding:** Use `PathfindingService`. NPCs should patrol random nodes and use simple Raycasting to detect and shoot at players.

## 4. Coding Standards
- **Services:** Always use `game:GetService("ServiceName")`.
- **Timing:** Use `task.wait()`, `task.spawn()`, and `task.delay()`. NEVER use `wait()`, `spawn()`, or `delay()`.
- **Variables:** camelCase for variables, PascalCase for Services and Classes, UPPER_SNAKE_CASE for constants.

## 5. UI Design
- Minimalist FPS UI. Health bar in bottom left, Ammo counter in bottom right.
- Crosshair must be a simple dot in the center of the screen.