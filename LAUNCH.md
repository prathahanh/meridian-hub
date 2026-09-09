# Meridian · starting a new game

Read this before writing anything. It is short and every line was paid for by a
bug that shipped.

## Where things are

    Meridian/
      main.luau        loader, key gate, the GAMES table      SHARED
      core.luau        flags, loops, controls registry        SHARED
      ui.luau          Maclib polish, headline, search        SHARED
      chrome/dashboard/key                                    SHARED
      games/*.luau     one file per game                      YOURS
      check.sh         run this before every commit

Two games are done: `ability_arena.luau` and `steal_an_egg.luau`. Steal An Egg
is the reference implementation. When you are unsure how something should look,
open it.

## Five sessions, one repo

- **Touch only your own `games/<game>.luau`.** Nothing else.
- The one exception is a single line in the `GAMES` table in `main.luau`. Add
  it, pull, push. It is the only line five sessions can collide on.
- If your game genuinely needs a change to a shared file, say so in chat before
  making it. Do not make it quietly. One session breaking `core.luau` breaks
  the other four.
- Work on `main`. Pull before you push.

## Your client, and only yours

Five sessions means five Roblox clients. Real runs them: Account Manager to
launch each account into its game, then Auto Attach -> Attach All Instances.
The MCP is the part that needs care.

**No MCP tool takes a client id.** `eval`, `start-job`, `execute-file` and the
rest all run in "the active client", and `set-active-client` is the only thing
that picks it.

**Re-asserting it is not enough, and this was measured with five sessions live.**
`set-active-client` returned "active client set to 14068" and the very next call
ran in another session's game. It happened on four separate calls in one hour.
The pointer is taken between any two calls, not between bursts, so there is no
sequence of calls that reliably holds it. Stop trying to hold it and make the
code survive losing it.

1. **Guard every script on its first line.**

        if game.PlaceId ~= <yours> then
            warn("[meridian] wrong client, place " .. tostring(game.PlaceId))
            return
        end

   A wrong landing becomes a no-op with a message instead of damage, so a retry
   costs nothing. This caught a load that would have put the whole hub into
   another session's client.

2. **Report through a file, not a return value.** `writefile("yours.json", ...)`
   in game, then read it from the shell. A return value comes back attributed to
   whichever client answered, which is worse than no answer at all. Save
   progressively, so a run that gets kicked still leaves what it learned.

3. **`execute-file` names the client it dispatched to.** Its reply says
   `scheduled: client 14068`, which is the only honest confirmation available.
   Read it every time; if it is the wrong pid, just fire again.

4. **Namespace your files.** The Real workspace folder is shared by all five
   sessions, and so is the git working tree. Prefix output files with your game
   and only ever `git add` your own paths.

Accounts live in Real's Account Manager. One per session, assigned up front, so
that two sessions never launch the same one.

## Adding a game

1. `cp games/_template.luau games/<game>.luau`
2. Fill in `GameId` and `Name` at the top
3. Add one line to `GAMES` in `main.luau`
4. `./check.sh games/<game>.luau` before every commit

## The rules that cost the most

**A feature nobody has watched succeed is not built.** On one day in Steal An
Egg, eleven switches turned out to do nothing, and every one of them looked
correct in the code. They were found by reading the hub's own journal during a
live run, not by reading the source. Watch it work or it does not count.

**Read the game's own client before trusting an endpoint name.** `SellAsset`
sells the tool in your hand, not the uid you send. `SellAllAssets` takes a list
and ignores it. `SetAutoSellState` takes a map of rarity names, not a boolean.
`Redeem` needs `{Kind = "Claim"}` or the server throws. All four looked obvious
and all four were wrong. Grep the game's LocalScripts for the call site and copy
the payload exactly.

**Names in a network map often have no remote behind them.** Steal An Egg names
eight endpoints across three systems that do not exist in the Network folder.
Ask the folder, not the map, and say so in the UI rather than shipping a switch
that cannot work.

**An impossible request on a timer is what gets accounts kicked.** Not movement,
not speed. Gate every repeated call, back it off when refused, and prefer
looking the answer up in the save over asking the server.

**Build is one function against 200 local registers.** Features go on a table at
file scope with a `wire`. `luau-analyze` cannot see the ceiling; `luau-compile`
can, and `check.sh` runs both.

**Nothing in `Module.Build` may yield.** It runs while the loader is still
assembling the window.

**No read-only panels.** Information arrives as behaviour: a notification when
something worth acting on appears, a purchase made at the right moment. A
column of text labels has been rejected three times.

## Done, for one game

1. Every switch has been watched working on a live client.
2. Nothing on screen cannot work. If the game has no remote for it, the control
   comes out.
3. It survives an hour unattended without a kick or a stall.
4. The tooltips read like a player wrote them.

## Shipping

`main` is where work happens. `stable` is what testers load. Merging main into
stable is a deliberate act, not a habit.
