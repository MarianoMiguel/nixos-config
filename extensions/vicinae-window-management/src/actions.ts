export type WindowAction = {
  id: string;
  title: string;
  section: string;
  keywords: string[];
};

export const actions: WindowAction[] = [
  { id: "hide-others", title: "Hide Other Applications", section: "Focus", keywords: ["hide", "minimize", "apps", "focus"] },
  { id: "show-all", title: "Show Hidden Applications", section: "Focus", keywords: ["show", "restore", "apps"] },

  { id: "center", title: "Center", section: "Common", keywords: ["middle", "position"] },
  { id: "reasonable-size", title: "Reasonable Size", section: "Common", keywords: ["comfortable", "sixty", "center"] },
  { id: "almost-maximize", title: "Almost Maximize", section: "Common", keywords: ["large", "ninety", "center"] },
  { id: "maximize", title: "Maximize", section: "Common", keywords: ["fill", "screen"] },
  { id: "maximize-height", title: "Maximize Height", section: "Common", keywords: ["vertical", "fill"] },
  { id: "maximize-width", title: "Maximize Width", section: "Common", keywords: ["horizontal", "fill"] },
  { id: "restore", title: "Restore Previous Geometry", section: "Common", keywords: ["undo", "previous", "size"] },
  { id: "toggle-fullscreen", title: "Toggle Fullscreen", section: "Common", keywords: ["full", "screen"] },

  { id: "left-half", title: "Left Half", section: "Halves", keywords: ["left", "half"] },
  { id: "center-half", title: "Center Half", section: "Halves", keywords: ["center", "half"] },
  { id: "right-half", title: "Right Half", section: "Halves", keywords: ["right", "half"] },
  { id: "top-half", title: "Top Half", section: "Halves", keywords: ["top", "half"] },
  { id: "bottom-half", title: "Bottom Half", section: "Halves", keywords: ["bottom", "half"] },

  { id: "first-third", title: "First Third", section: "Thirds", keywords: ["left", "third"] },
  { id: "first-two-thirds", title: "First Two Thirds", section: "Thirds", keywords: ["left", "two", "thirds"] },
  { id: "center-third", title: "Center Third", section: "Thirds", keywords: ["center", "third"] },
  { id: "last-two-thirds", title: "Last Two Thirds", section: "Thirds", keywords: ["right", "two", "thirds"] },
  { id: "last-third", title: "Last Third", section: "Thirds", keywords: ["right", "third"] },
  { id: "top-third", title: "Top Third", section: "Thirds", keywords: ["top", "third"] },
  { id: "top-two-thirds", title: "Top Two Thirds", section: "Thirds", keywords: ["top", "two", "thirds"] },
  { id: "middle-third", title: "Middle Third", section: "Thirds", keywords: ["middle", "third"] },
  { id: "bottom-two-thirds", title: "Bottom Two Thirds", section: "Thirds", keywords: ["bottom", "two", "thirds"] },
  { id: "bottom-third", title: "Bottom Third", section: "Thirds", keywords: ["bottom", "third"] },
  { id: "top-center-two-thirds", title: "Top Center Two Thirds", section: "Thirds", keywords: ["top", "center", "thirds"] },

  { id: "first-fourth", title: "First Fourth", section: "Fourths", keywords: ["first", "left", "fourth"] },
  { id: "second-fourth", title: "Second Fourth", section: "Fourths", keywords: ["second", "fourth"] },
  { id: "third-fourth", title: "Third Fourth", section: "Fourths", keywords: ["third", "fourth"] },
  { id: "last-fourth", title: "Last Fourth", section: "Fourths", keywords: ["last", "right", "fourth"] },
  { id: "top-left-quarter", title: "Top Left Quarter", section: "Quarters", keywords: ["top", "left", "quarter"] },
  { id: "top-right-quarter", title: "Top Right Quarter", section: "Quarters", keywords: ["top", "right", "quarter"] },
  { id: "bottom-left-quarter", title: "Bottom Left Quarter", section: "Quarters", keywords: ["bottom", "left", "quarter"] },
  { id: "bottom-right-quarter", title: "Bottom Right Quarter", section: "Quarters", keywords: ["bottom", "right", "quarter"] },

  { id: "top-left-sixth", title: "Top Left Sixth", section: "Sixths", keywords: ["top", "left", "sixth"] },
  { id: "top-center-sixth", title: "Top Center Sixth", section: "Sixths", keywords: ["top", "center", "sixth"] },
  { id: "top-right-sixth", title: "Top Right Sixth", section: "Sixths", keywords: ["top", "right", "sixth"] },
  { id: "bottom-left-sixth", title: "Bottom Left Sixth", section: "Sixths", keywords: ["bottom", "left", "sixth"] },
  { id: "bottom-center-sixth", title: "Bottom Center Sixth", section: "Sixths", keywords: ["bottom", "center", "sixth"] },
  { id: "bottom-right-sixth", title: "Bottom Right Sixth", section: "Sixths", keywords: ["bottom", "right", "sixth"] },

  { id: "move-left", title: "Move to Left Edge", section: "Move", keywords: ["move", "left", "edge"] },
  { id: "move-right", title: "Move to Right Edge", section: "Move", keywords: ["move", "right", "edge"] },
  { id: "move-up", title: "Move to Top Edge", section: "Move", keywords: ["move", "up", "top", "edge"] },
  { id: "move-down", title: "Move to Bottom Edge", section: "Move", keywords: ["move", "down", "bottom", "edge"] },
  { id: "previous-display", title: "Move to Previous Display", section: "Move", keywords: ["monitor", "display", "previous"] },
  { id: "next-display", title: "Move to Next Display", section: "Move", keywords: ["monitor", "display", "next"] },
  { id: "previous-workspace", title: "Move to Previous Workspace", section: "Move", keywords: ["workspace", "space", "previous"] },
  { id: "next-workspace", title: "Move to Next Workspace", section: "Move", keywords: ["workspace", "space", "next"] },
];
