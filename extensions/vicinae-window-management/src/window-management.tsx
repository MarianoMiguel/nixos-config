import { Action, ActionPanel, Icon, List } from "@vicinae/api";

import { actions } from "./actions";
import { executeAction } from "./execute";

export default function WindowManagement() {
  const sections = [...new Set(actions.map(action => action.section))];

  return (
    <List searchBarPlaceholder="Search window actions...">
      {sections.map(section => (
        <List.Section key={section} title={section}>
          {actions
            .filter(action => action.section === section)
            .map(action => (
              <List.Item
                key={action.id}
                title={action.title}
                keywords={action.keywords}
                icon={Icon.AppWindowGrid3x3}
                actions={
                  <ActionPanel>
                    <Action
                      title={action.title}
                      icon={Icon.AppWindowGrid3x3}
                      onAction={() => executeAction(action.id, action.title)}
                    />
                  </ActionPanel>
                }
              />
            ))}
        </List.Section>
      ))}
    </List>
  );
}
