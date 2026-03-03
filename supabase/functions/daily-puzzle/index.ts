import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Backbite algorithm for Hamiltonian path generation
function generateHamiltonianPath(
  gridSize: number,
  walls: { row: number; col: number }[],
): { row: number; col: number }[] | null {
  const totalCells = gridSize * gridSize - walls.length;
  const wallSet = new Set(walls.map((w) => `${w.row},${w.col}`));

  // Initialize with a single cell
  const getNeighbors = (
    row: number,
    col: number,
  ): { row: number; col: number }[] => {
    const dirs = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];
    return dirs
      .map(([dr, dc]) => ({ row: row + dr, col: col + dc }))
      .filter(
        (p) =>
          p.row >= 0 &&
          p.row < gridSize &&
          p.col >= 0 &&
          p.col < gridSize &&
          !wallSet.has(`${p.row},${p.col}`),
      );
  };

  // Start from a random non-wall cell
  let startRow: number, startCol: number;
  do {
    startRow = Math.floor(Math.random() * gridSize);
    startCol = Math.floor(Math.random() * gridSize);
  } while (wallSet.has(`${startRow},${startCol}`));

  let path: { row: number; col: number }[] = [
    { row: startRow, col: startCol },
  ];
  const maxIterations = totalCells * 200;

  for (let iter = 0; iter < maxIterations; iter++) {
    if (path.length >= totalCells) break;

    const tail = path[path.length - 1];
    const neighbors = getNeighbors(tail.row, tail.col).filter(
      (n) => !path.some((p) => p.row === n.row && p.col === n.col),
    );

    if (neighbors.length > 0) {
      // Extend path
      const next = neighbors[Math.floor(Math.random() * neighbors.length)];
      path.push(next);
    } else {
      // Backbite: remove from tail end and try to reconnect
      const head = path[0];
      const headNeighbors = getNeighbors(head.row, head.col).filter(
        (n) =>
          path.some((p) => p.row === n.row && p.col === n.col) &&
          !(n.row === path[1]?.row && n.col === path[1]?.col),
      );

      if (headNeighbors.length > 0) {
        const target =
          headNeighbors[Math.floor(Math.random() * headNeighbors.length)];
        const targetIdx = path.findIndex(
          (p) => p.row === target.row && p.col === target.col,
        );

        // Reverse the path from start to target, making target the new head
        path = [...path.slice(0, targetIdx + 1).reverse(), ...path.slice(targetIdx + 1)];
      }
    }
  }

  return path.length >= totalCells ? path : null;
}

function generatePuzzle(gridSize: number, difficulty: string) {
  // Determine number of walls based on difficulty
  const wallCount =
    difficulty === "easy"
      ? 0
      : difficulty === "medium"
        ? Math.floor(gridSize * 0.3)
        : difficulty === "hard"
          ? Math.floor(gridSize * 0.5)
          : Math.floor(gridSize * 0.6);

  // Generate random walls
  const walls: { row: number; col: number }[] = [];
  const usedCells = new Set<string>();

  for (let i = 0; i < wallCount; i++) {
    let row: number, col: number;
    let attempts = 0;
    do {
      row = Math.floor(Math.random() * gridSize);
      col = Math.floor(Math.random() * gridSize);
      attempts++;
    } while (usedCells.has(`${row},${col}`) && attempts < 100);

    if (!usedCells.has(`${row},${col}`)) {
      walls.push({ row, col });
      usedCells.add(`${row},${col}`);
    }
  }

  // Generate Hamiltonian path
  let path: { row: number; col: number }[] | null = null;
  let retries = 0;
  while (!path && retries < 50) {
    path = generateHamiltonianPath(gridSize, walls);
    retries++;
    if (!path && retries >= 50) {
      // Reduce walls and retry
      walls.pop();
      retries = 0;
    }
  }

  if (!path) {
    throw new Error("Failed to generate puzzle");
  }

  // Select waypoints along the path
  const numWaypoints =
    difficulty === "easy"
      ? 3
      : difficulty === "medium"
        ? 3
        : difficulty === "hard"
          ? 4
          : 5;

  const waypoints: { order: number; row: number; col: number }[] = [];
  // First waypoint is always the start
  waypoints.push({ order: 1, row: path[0].row, col: path[0].col });

  // Distribute remaining waypoints evenly along the path
  const spacing = Math.floor(path.length / numWaypoints);
  for (let i = 1; i < numWaypoints - 1; i++) {
    const idx = i * spacing;
    waypoints.push({ order: i + 1, row: path[idx].row, col: path[idx].col });
  }

  // Last waypoint is always the end
  waypoints.push({
    order: numWaypoints,
    row: path[path.length - 1].row,
    col: path[path.length - 1].col,
  });

  // Generate solution hash (hash of the path coordinates)
  const pathStr = path.map((p) => `${p.row},${p.col}`).join("|");
  const solutionHash = btoa(pathStr).slice(0, 32);

  // Par time based on grid size and difficulty
  const basePar = gridSize * gridSize * 2;
  const parMultiplier =
    difficulty === "easy"
      ? 1.5
      : difficulty === "medium"
        ? 1.3
        : difficulty === "hard"
          ? 1.1
          : 1.0;
  const parTimeSeconds = Math.round(basePar * parMultiplier);

  return {
    gridSize,
    waypoints,
    walls,
    solutionHash,
    difficulty,
    parTimeSeconds,
  };
}

serve(async (req: Request) => {
  // Handle CORS
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
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Generate puzzle for tomorrow
    const tomorrow = new Date();
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    const puzzleDate = tomorrow.toISOString().split("T")[0];

    // Check if puzzle already exists
    const { data: existing } = await supabase
      .from("puzzles")
      .select("id")
      .eq("puzzle_date", puzzleDate)
      .maybeSingle();

    if (existing) {
      return new Response(
        JSON.stringify({ message: "Puzzle already exists for " + puzzleDate }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Determine difficulty based on day of week (Mon=easy, Sun=expert)
    const dayOfWeek = tomorrow.getUTCDay(); // 0=Sun, 1=Mon, ...
    const dayIndex = dayOfWeek === 0 ? 7 : dayOfWeek;

    let gridSize: number;
    let difficulty: string;

    if (dayIndex <= 2) {
      gridSize = 5;
      difficulty = "easy";
    } else if (dayIndex <= 4) {
      gridSize = 6;
      difficulty = "medium";
    } else if (dayIndex <= 6) {
      gridSize = 7;
      difficulty = "hard";
    } else {
      gridSize = 8;
      difficulty = "expert";
    }

    const puzzle = generatePuzzle(gridSize, difficulty);

    const { error } = await supabase.from("puzzles").insert({
      puzzle_date: puzzleDate,
      grid_size: puzzle.gridSize,
      waypoints: puzzle.waypoints,
      walls: puzzle.walls,
      solution_hash: puzzle.solutionHash,
      difficulty: puzzle.difficulty,
      par_time_seconds: puzzle.parTimeSeconds,
    });

    if (error) throw error;

    return new Response(
      JSON.stringify({
        message: "Puzzle generated for " + puzzleDate,
        difficulty,
        gridSize,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 201,
      },
    );
  } catch (error) {
    console.error("Error generating puzzle:", error);
    return new Response(
      JSON.stringify({ error: "Failed to generate puzzle" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      },
    );
  }
});
