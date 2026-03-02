# ROBLOX PROJECT: URBAN FPS BATTLEGROUNDS

## 1. Core Tech & Style
- **Engine:** Roblox Luau. Use strict typing (`--!strict`) on all scripts.
- **Avatar:** R15.
- **Perspective:** First-Person ONLY. `StarterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson`.
- **Map Loading:** Assume `Workspace.StreamingEnabled = true`. Scripts must account for parts not being loaded immediately (use `WaitForChild`).
- **Map Design:** Procedural dense NYC-style city (800x800) with alleyways, multi-story hollow buildings, and walkable stairs.

## 2. Dependencies & External Libraries
- **RBX_Toolbox:** Located in `ReplicatedStorage`. Used exclusively for inventory management and weapon pickups (do NOT use standard Roblox Tools).
- **Character-Realism:** Located in `ReplicatedStorage`. Applied to both the local player and AI NPCs for realistic spine bending, leaning, and movement.

## 3. Game Architecture
- **Framework:** Use Rojo structure (`src/server`, `src/client`, `src/shared`).
- **Weapon System:** Weapons use a custom Raycast system (`workspace:Raycast()`). 
- **FPS Viewmodel:** Client uses a `ViewmodelController` to attach physical cleaned weapon models (cloned from `ReplicatedStorage/Weapons`) to the `CurrentCamera`.
- **Security:** NEVER trust the client. Server must verify raycast distances and line-of-sight before applying damage to prevent exploiters.
- **Scoring:** `Leaderstats` tracks "Kills" and "Deaths". Killing an AI NPC counts exactly the same as killing a real player.

## 4. The AI System
- **Testing Target:** For now, the server must ONLY generate exactly 1 NPC for testing purposes. Do not backfill to 25 entities yet.
- **Logic:** `ServerScriptService/AISpawner.luau` should spawn just a single NPC to test pathfinding and combat.
- **NPC Design:** NPCs use `PathfindingService`. They must use `HumanoidDescription` fetched via UserID so they look like real Roblox players, and must have the `Animate` script loaded so they don't float.

## 5. Coding Standards
- **Services:** Always use `game:GetService("ServiceName")`.
- **Timing:** Use `task.wait()`, `task.spawn()`, and `task.delay()`. NEVER use `wait()`, `spawn()`, or `delay()`.
- **Variables:** camelCase for variables, PascalCase for Services and Classes, UPPER_SNAKE_CASE for constants.

## 6. UI Design
- Minimalist FPS UI. Health bar in bottom left, Ammo counter in bottom right, Current Weapon Name at bottom center.
- Crosshair must be a simple dot in the center of the screen.

## 7. Github Backup
- Use the below command whenever I ask to back up to github:
  `git add -A && git commit -m "your message" && git push`