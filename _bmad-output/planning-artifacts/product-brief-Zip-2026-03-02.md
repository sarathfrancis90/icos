---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - PLAN.md
date: 2026-03-02
author: Sarathfrancis
---

# Product Brief: Icos (Zip)

## Executive Summary

**Icos** is a premium mobile puzzle game for Android and iOS where players draw a continuous path through a grid, connecting numbered waypoints in order while filling every cell. Inspired by LinkedIn's Zip game, Icos differentiates through superior UI/UX with fluid animations and haptic feedback, a group-based social system with daily leaderboards, and an offline-first architecture that lets players solve puzzles without internet connectivity.

The product targets the rapidly growing casual puzzle market — validated by the success of Wordle, NYT Games, and LinkedIn's own puzzle suite — while carving its own niche through social group mechanics that transform a solo puzzle into a shared daily ritual among friends, families, and coworkers.

---

## Core Vision

### Problem Statement

Daily puzzle games have proven massive engagement (Wordle's viral growth, NYT Games' subscriber retention, LinkedIn's Zip), but existing offerings suffer from key limitations:

1. **No meaningful social competition** — most puzzle games are solitary experiences with no way to compare performance against friends in real-time
2. **Platform lock-in** — LinkedIn's Zip requires being on LinkedIn; NYT puzzles require a subscription
3. **No offline support** — existing solutions require connectivity, excluding commuters, travelers, and users in low-connectivity areas
4. **Limited accessibility** — few puzzle games prioritize colorblind modes, screen reader support, or reduced motion settings

### Problem Impact

- Puzzle enthusiasts lack a dedicated, social-first daily puzzle experience outside of walled gardens (LinkedIn, NYT)
- Friend groups and coworkers who enjoy daily puzzles have no easy way to compete and compare without sharing screenshots manually
- Users in low-connectivity environments (commutes, flights, rural areas) are excluded from the daily puzzle ritual
- Users with visual impairments or accessibility needs are underserved by current puzzle game UIs

### Why Existing Solutions Fall Short

| Competitor | Strength | Gap |
|-----------|----------|-----|
| **LinkedIn Zip** | Proven game mechanic, large user base | Locked to LinkedIn platform, no groups/leaderboards, no offline, limited social sharing |
| **Wordle / NYT Games** | Strong brand, daily habit formation | Subscription paywall, no real-time group leaderboards, no path-drawing mechanic |
| **Generic puzzle apps** | Available on app stores | Ad-heavy, no daily ritual, poor UX, no social features |

None offer the combination of: a compelling Hamiltonian path puzzle + private group leaderboards + offline-first play + spoiler-free sharing + accessibility-first design.

### Proposed Solution

Icos delivers:

- **One daily puzzle for everyone** — same puzzle, same difficulty curve (Monday=easy 5x5, Sunday=hard 8x8), creating a shared experience
- **Group-based social competition** — create private groups (up to 50 members) with daily and weekly leaderboards ranked by hints used, then solve time
- **Offline-first architecture** — puzzles pre-cached 24 hours in advance; play anywhere, sync results when back online
- **Spoiler-free sharing** — Wordle-style abstract result cards that show performance without revealing the solution
- **Beautiful, accessible UI** — fluid path-drawing animations, haptic feedback, colorblind mode, screen reader support, and multiple themes

The puzzle engine runs entirely client-side for instant feedback, with server-side re-validation for anti-cheat integrity.

### Key Differentiators

1. **Group leaderboards** — private groups turn daily puzzles into a social ritual (friends, coworkers, family)
2. **Offline-first** — no connectivity required to play; results sync automatically
3. **Accessibility-first** — colorblind modes, screen reader support, reduced motion, large text mode
4. **Platform-independent** — standalone app on iOS and Android, no platform lock-in
5. **Spoiler-free sharing** — share results on any social platform without revealing solutions
6. **Ghost Race (post-MVP)** — watch animated replays of friends' solve paths overlaid on yours
7. **Path Heatmap (post-MVP)** — see aggregate difficulty visualization of where all players struggled

---

## Target Users

### Primary Users

**Persona 1: "Daily Puzzler Dana"**
- **Profile**: 28-35 year old professional who plays Wordle, NYT Connections, or LinkedIn Zip daily during morning coffee or commute
- **Motivation**: Enjoys the ritual of a daily brain challenge; likes comparing results with friends
- **Current pain**: Screenshots solve-time comparisons in group chats are clunky; LinkedIn Zip has no real leaderboard
- **Icos value**: One-tap group leaderboard shows where she ranks among friends each day; spoiler-free sharing to Instagram Stories
- **Success moment**: Seeing she beat her coworker's time and sending a share card to the group chat

**Persona 2: "Competitive Chris"**
- **Profile**: 22-40 year old who optimizes solve times, tracks personal stats, maintains long streaks
- **Motivation**: Self-improvement, streak maintenance, being #1 on leaderboards
- **Current pain**: No good stats tracking or streak mechanics in existing path puzzles
- **Icos value**: Detailed statistics (average time, distribution chart), streak tracking with freeze protection, group ranking badges
- **Success moment**: Hitting a 30-day streak, earning the top rank in multiple groups

**Persona 3: "Social Sam"**
- **Profile**: 25-45 year old who creates and manages friend/coworker groups
- **Motivation**: Bringing people together through shared daily activities
- **Current pain**: Hard to organize puzzle competitions; no easy invite/group system in existing games
- **Icos value**: One-tap group creation, shareable invite codes/QR/deep links, group streak tracking
- **Success moment**: Their office group of 15 people all solving the daily puzzle and competing on the leaderboard

### Secondary Users

- **Casual discoverers** — people who receive a share card or group invite and try the game for the first time (anonymous play with zero friction)
- **Accessibility-focused users** — players who need colorblind modes, screen reader support, or large text to enjoy puzzle games

### User Journey

1. **Discovery** — receives a spoiler-free share card on social media or a group invite link from a friend
2. **Onboarding** — opens app, starts playing immediately (anonymous auth, no sign-up wall); solves first puzzle within 60 seconds of download
3. **Core Usage** — daily ritual: open app, solve today's puzzle, check group leaderboard, share result
4. **Aha Moment** — joins first group, sees friends' times, realizes this is a shared daily competition
5. **Retention Loop** — streak maintenance + daily group competition + notification nudges ("You're the last one! 9/10 members have solved today")
6. **Expansion** — creates own groups (work team, family), invites more people, growing the network organically

---

## Success Metrics

### User Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Time to first puzzle solve | < 90 seconds from app open | Analytics event tracking |
| Daily puzzle completion rate | > 70% of DAU | Completed puzzles / daily active users |
| 7-day retention | > 40% | Users returning 7 days after first solve |
| 30-day retention | > 25% | Users returning 30 days after first solve |
| Group join rate | > 30% of registered users in at least 1 group | Group membership / registered users |
| Streak maintenance | > 50% of active users maintain 3+ day streak | Streak data analysis |
| Share rate | > 15% of daily solvers share their result | Share events / daily completions |

### Business Objectives

**3-Month Goals (Post-Launch):**
- 5,000+ monthly active users
- 500+ groups created
- 4.5+ App Store rating
- < 1% crash rate

**12-Month Goals:**
- 50,000+ monthly active users
- Organic growth driven by group invites and social sharing
- Explore sustainable monetization (optional cosmetics, premium themes) without ads

### Key Performance Indicators

| KPI | Definition | Target |
|-----|-----------|--------|
| DAU/MAU ratio | Daily engagement health | > 0.4 (strong daily habit) |
| Viral coefficient | New users per existing user via invites/shares | > 0.5 |
| Avg. group size | Social engagement depth | 8-15 members |
| Puzzle load time | Technical performance | < 200ms (cached), < 500ms (network) |
| Path drawing FPS | Core UX quality | 60 FPS minimum |
| App cold start | First impression | < 2 seconds |

---

## MVP Scope

### Core Features

**Must-Have for Launch (Phases 1-3 of PLAN.md):**

1. **Puzzle Engine**
   - Grid rendering with numbered waypoints and wall barriers
   - Touch-based path drawing with smooth drag gestures
   - Path validation (continuous, visits all cells, hits waypoints in order, respects walls)
   - Undo/redo (drag backward or tap undo button)
   - Reset puzzle
   - Completion detection with celebration animation

2. **Daily Puzzle System**
   - One new puzzle per day, same for all users
   - Difficulty progression: Mon=easy (5x5) through Sun=hard (8x8)
   - Timer (hidden during play, shown on completion)
   - Puzzle pre-generation (30 days ahead via Edge Function)

3. **Hint System**
   - Reveal next segment (2-3 cells)
   - 3 free hints per day

4. **Streaks & Statistics**
   - Current streak, longest streak, total puzzles solved
   - Average solve time
   - 1 streak freeze per week

5. **User Management**
   - Anonymous play (immediate, no sign-up wall)
   - Account creation (email, Google, Apple Sign-In)
   - Account linking (anonymous to full account, no data loss)
   - Profile (display name, preset avatar)

6. **Groups & Leaderboards**
   - Create/join/leave groups
   - Invite via 6-character code, deep link, or QR
   - Group daily leaderboard (ranked by hints used, then solve time)
   - Group weekly leaderboard
   - Max 50 members per group

7. **Sharing**
   - Spoiler-free result sharing (grid size, time, abstract path visualization)
   - Share to social media / clipboard
   - Group invite sharing

8. **Offline Support**
   - Offline-first: puzzle cached 24h in advance
   - Play without internet, sync results when online
   - 7 bundled fallback puzzles for first launch

### Out of Scope for MVP

- Practice mode (unlimited random puzzles)
- Archive (replay past puzzles)
- Global leaderboard (top 100)
- Achievement/badge system
- Ghost Race feature
- Path Heatmap
- Speed run mode
- Weekly challenge (large 9x9/10x10 puzzles)
- Group chat
- Head-to-head real-time mode
- Friend system (outside of groups)
- Spectator replay
- Seasonal themes
- Path color customization
- Advanced accessibility (screen reader, one-handed mode) — basic colorblind support included in MVP
- Monetization features

### MVP Success Criteria

| Criteria | Gate |
|----------|------|
| Core puzzle mechanic is engaging | > 60% of beta testers complete 5+ puzzles |
| Social loop works | > 25% of beta users join at least 1 group |
| Offline play reliable | 0 data loss incidents during offline-to-online sync testing |
| Performance acceptable | 60 FPS path drawing, < 2s cold start on mid-range devices |
| Store-ready quality | < 1% crash rate, 4.0+ beta rating |

### Future Vision

**Post-MVP Roadmap (Phase 5+):**

- **Practice Mode** — unlimited randomly generated puzzles for users who want more than the daily challenge
- **Achievement System** — badges for milestones (streak records, speed achievements, social goals)
- **Ghost Race** — after both players solve, watch animated replays overlaid — like racing game ghosts
- **Path Heatmap** — aggregate visualization showing where players globally struggled on each puzzle
- **Puzzle DNA** — unique visual fingerprint generated from each solve path, shareable as profile art
- **Weekly Challenges** — large 9x9/10x10 puzzles released on Saturdays
- **Global Leaderboard** — top 100 daily solvers worldwide
- **Cosmetic Customization** — themes, path colors, grid styles, celebration animations (potential monetization)
- **Group Streak** — collective group streak tracking (% of members who solved today)

---

## Technical Foundation (Reference)

- **Frontend**: Flutter 3.x (Dart), CustomPainter for game canvas, Riverpod for state management, GoRouter for navigation
- **Backend**: Supabase (PostgreSQL, Auth, Realtime, Edge Functions)
- **Analytics**: Firebase (Analytics, Crashlytics, Performance, Remote Config)
- **Push Notifications**: Firebase Cloud Messaging
- **CI/CD**: GitHub Actions + Fastlane
- **Architecture**: Offline-first, client-side puzzle engine with server-side re-validation for anti-cheat
