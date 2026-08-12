import { environment } from "@vicinae/api";

import { actions } from "./actions";
import { executeAction } from "./execute";

export default async function RunCommand() {
  const action = actions.find(item => item.id === environment.commandName);
  await executeAction(environment.commandName, action?.title);
}
