import { httpServerHandler } from "cloudflare:node";

import "./src/server.ts";

export default httpServerHandler({ port: 8080 });
