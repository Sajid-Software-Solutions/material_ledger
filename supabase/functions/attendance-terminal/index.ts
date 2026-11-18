import { handleTerminal } from "./handler.ts";

Deno.serve((request) => handleTerminal(request));
