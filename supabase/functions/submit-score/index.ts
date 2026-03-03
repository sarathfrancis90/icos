import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Health check
  const url = new URL(req.url);
  if (url.pathname.endsWith("/health")) {
    return new Response(JSON.stringify({ status: "ok" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // Get auth token from request
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authHeader } },
      },
    );

    // Get user
    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check if user is banned
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("is_banned")
      .eq("id", user.id)
      .single();

    if (profile?.is_banned) {
      return new Response(JSON.stringify({ error: "Account suspended" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const body = await req.json();
    const { puzzle_date, time_seconds, hints_used, undos_used, path } = body;

    if (!puzzle_date || time_seconds === undefined || !path) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limiting: check recent submissions (10/hour)
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count: recentAttempts } = await supabaseAdmin
      .from("puzzle_attempts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", oneHourAgo);

    if (recentAttempts && recentAttempts >= 10) {
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded. Try again later." }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if already completed today's puzzle
    const { data: existingAttempt } = await supabaseAdmin
      .from("puzzle_attempts")
      .select("id")
      .eq("user_id", user.id)
      .eq("puzzle_date", puzzle_date)
      .eq("completed", true)
      .maybeSingle();

    if (existingAttempt) {
      return new Response(
        JSON.stringify({ error: "Already completed this puzzle" }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get puzzle to validate
    const { data: puzzle, error: puzzleError } = await supabaseAdmin
      .from("puzzles")
      .select("*")
      .eq("puzzle_date", puzzle_date)
      .single();

    if (puzzleError || !puzzle) {
      return new Response(JSON.stringify({ error: "Puzzle not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate the path (server-side validation)
    const isValid = validatePath(
      puzzle.grid_size,
      puzzle.waypoints,
      puzzle.walls,
      path,
    );

    // Record attempt
    const { error: insertError } = await supabaseAdmin
      .from("puzzle_attempts")
      .insert({
        user_id: user.id,
        puzzle_id: puzzle.id,
        puzzle_date,
        time_seconds,
        hints_used: hints_used || 0,
        undos_used: undos_used || 0,
        completed: isValid,
        path,
        completed_at: isValid ? new Date().toISOString() : null,
      });

    if (insertError) {
      console.error("Insert error:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to save attempt" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update streak if completed
    if (isValid) {
      await updateStreak(supabaseAdmin, user.id, puzzle_date);
    }

    return new Response(
      JSON.stringify({
        completed: isValid,
        message: isValid ? "Puzzle solved!" : "Invalid solution",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    console.error("Error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function validatePath(
  gridSize: number,
  waypoints: { order: number; row: number; col: number }[],
  walls: { row: number; col: number }[],
  path: number[][],
): boolean {
  const wallSet = new Set(walls.map((w: { row: number; col: number }) => `${w.row},${w.col}`));
  const totalNonWallCells = gridSize * gridSize - walls.length;

  // Path must cover all non-wall cells
  if (path.length !== totalNonWallCells) return false;

  // Check no duplicates and all valid
  const visited = new Set<string>();
  for (let i = 0; i < path.length; i++) {
    const [row, col] = path[i];
    const key = `${row},${col}`;

    if (row < 0 || row >= gridSize || col < 0 || col >= gridSize) return false;
    if (wallSet.has(key)) return false;
    if (visited.has(key)) return false;
    visited.add(key);

    // Check adjacency
    if (i > 0) {
      const [prevRow, prevCol] = path[i - 1];
      if (Math.abs(row - prevRow) + Math.abs(col - prevCol) !== 1)
        return false;
    }
  }

  // Check waypoints are visited in order
  const sortedWaypoints = [...waypoints].sort(
    (a: { order: number }, b: { order: number }) => a.order - b.order,
  );
  let waypointIdx = 0;
  for (const [row, col] of path) {
    if (waypointIdx < sortedWaypoints.length) {
      const wp = sortedWaypoints[waypointIdx];
      if (row === wp.row && col === wp.col) {
        waypointIdx++;
      }
    }
  }

  return waypointIdx === sortedWaypoints.length;
}

async function updateStreak(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  puzzleDate: string,
) {
  const today = new Date(puzzleDate);
  const yesterday = new Date(today);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  const yesterdayStr = yesterday.toISOString().split("T")[0];

  // Get or create streak record
  const { data: streak } = await supabase
    .from("streaks")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (!streak) {
    // Create initial streak
    await supabase.from("streaks").insert({
      user_id: userId,
      current_streak: 1,
      longest_streak: 1,
      last_solve_date: puzzleDate,
    });
    return;
  }

  let newStreak = 1;

  if (streak.last_solve_date === yesterdayStr) {
    // Consecutive day — extend streak
    newStreak = streak.current_streak + 1;
  } else if (streak.last_solve_date === puzzleDate) {
    // Already solved today — no change
    return;
  } else {
    // Check if streak freeze was available
    const daysSinceLastSolve = Math.floor(
      (today.getTime() - new Date(streak.last_solve_date).getTime()) /
        (1000 * 60 * 60 * 24),
    );

    if (daysSinceLastSolve === 2 && streak.freeze_count > 0) {
      // Apply streak freeze for yesterday
      newStreak = streak.current_streak + 1;

      // Check weekly freeze reset
      const weekStart = getWeekStart(today);
      const weekStartStr = weekStart.toISOString().split("T")[0];

      let freezeCount = streak.freeze_count - 1;
      if (streak.freeze_reset_week_start !== weekStartStr) {
        freezeCount = 0; // Reset used freeze, give back 1 next week
      }

      await supabase
        .from("streaks")
        .update({
          current_streak: newStreak,
          longest_streak: Math.max(newStreak, streak.longest_streak),
          last_solve_date: puzzleDate,
          freeze_count: freezeCount,
          last_freeze_used_at: yesterdayStr,
          freeze_reset_week_start: weekStartStr,
        })
        .eq("user_id", userId);
      return;
    }
    // Streak broken
    newStreak = 1;
  }

  await supabase
    .from("streaks")
    .update({
      current_streak: newStreak,
      longest_streak: Math.max(newStreak, streak.longest_streak),
      last_solve_date: puzzleDate,
    })
    .eq("user_id", userId);
}

function getWeekStart(date: Date): Date {
  const d = new Date(date);
  const day = d.getUTCDay();
  const diff = d.getUTCDate() - day + (day === 0 ? -6 : 1);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), diff));
}
