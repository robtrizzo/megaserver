import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/$404")({
  component: () => (
    <div className="min-h-screen bg-linear-to-b from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center text-white text-2xl">
      Page not found
    </div>
  ),
});
