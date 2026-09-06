+++
title = "Pinch Points - a Rust game with crabs"
date = 2026-09-06
path = "pinch-points-a-rust-game-with-crabs"

[taxonomies]
tags=["Rust", "game", "AI"]
+++

[Pinch Points](https://github.com/agourlay/pinch-points) is a kid-friendly routing game for 1-6 players, built in Rust with Bevy.

In this game, players compete to save the most crabs by routing them to their respective castles.

Check out what it looks like!

{{ figure(src="/2026-09-06/menu.png", alt="Game menu", caption="A nice home menu") }}
{{ figure(src="/2026-09-06/versus.png", alt="Versus mode", caption="The main versus mode, with multiplayer support") }}
{{ figure(src="/2026-09-06/puzzles.png", alt="Puzzles", caption="And 100 puzzles to solve") }}

You can install it from:
- [prebuilt binaries](https://github.com/agourlay/pinch-points/releases)
- `crates.io` with `cargo install --locked pinch-points`

The rest of the post is not the usual technical deep-dive article found on this blog.

Rather, it is my experience using **AI** to create a video game and what I learned in the process.

## Motivation

The game is based on the mechanics of `ChuChuRocket!` developed by Sonic Team and released in 1999 on the Dreamcast.

In this game, up to four players compete to save mice from cats by guiding them into their rockets by placing arrows on a board.

{{ figure(src="/2026-09-06/chuchu-cover.jpg", alt="Game Cover", caption="An iconic game cover for the Dreamcast") }}
{{ figure(src="/2026-09-06/chuchu-game.jpg", alt="Game mode", caption="The main game mode") }}

I was very fond of this game as a teenager; the gameplay is fast and so simple that everyone gets it and has fun.

As a programmer, I always thought that I could try to create something with similar gameplay while adding a few twists to modernize it and spice things up.

First, the theme: no more mice and cats in space. Given how much I like Rust, I wanted to make it about crabs!

I had a clear idea for the theme and the changes I wanted to make. This led me to think that creating this game could be a well-scoped task to gain experience with AI code generation.

After iterating on a specification document, I handed it over to `Claude Code` with Opus 5 and experienced the magic of generative coding firsthand.

## AI iterations

The first iteration took around an hour and was, retrospectively, by far the biggest productivity gain.
All the boilerplate required to bootstrap the project and wire things together. The basic structure of the game was there; at first I was very satisfied.

At this point, however, the game was far from being done, because my specifications were not precise enough.

What followed was a long and somewhat tedious process of going back and forth to implement certain things exactly as I wanted.

As expected, I did not know exactly what I wanted until I started playing the game myself!

Not only were there a **lot** of bugs to fix, but new changes would often break things elsewhere in the game.

While the coding agent was excellent at performing localized tasks, it was simply not good at preserving the global consistency of the game!

For this reason, I started putting constant pressure on the agent to improve code quality.

An easy first step is to look at code coverage to guide the generation of missing unit tests.

This helps prevent regressions but it is not enough to improve code quality.

After checking the code superficially, I would find myself repeatedly asking for:
- splitting large non-cohesive files
- splitting large structs
- introducing missing enums to replace fragile if/else cascades
- adding debug assertions

The quality would slowly increase but it required regular attention.

## End result

To be honest, I have mixed feelings about this experience.

On one hand, I am pretty satisfied with the game, I find it fun, and I've received some good feedback.

On the other hand, I am not satisfied with the creative process and that is not because AI is bad.

Quite the opposite: in many coding tasks, I found it surprisingly capable.

My main issues are related to ownership and mastery.

Although I precisely specified every aspect of the game through **many** playtests, I still feel like I do not own this game.

What I do have is a 50 KLOC codebase whose internals I don't fully understand — unlike my other side projects, which I have crafted with care.

You got the thing you asked for, but because you didn't build it yourself, you don't feel that it is truly yours.

As the saying goes, "Be careful what you wish for!"

In any case, the game exists now, so you might as well enjoy it.
