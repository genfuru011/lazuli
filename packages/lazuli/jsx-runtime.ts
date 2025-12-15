import { createComponent } from "npm:solid-js";

// Helper to escape HTML
const escape = (s: string) => s
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

export function jsx(tag: any, props: any) {
  const { children, ...attrs } = props || {};

  if (typeof tag === "function") {
    return createComponent(tag, props);
  }

  // Intrinsic element
  let attrStr = "";
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "className") {
      attrStr += ` class="${escape(String(value))}"`;
    } else {
      attrStr += ` ${key}="${escape(String(value))}"`;
    }
  }

  let childrenStr = "";
  const processChild = (child: any) => {
    if (Array.isArray(child)) {
      child.forEach(processChild);
    } else if (child && typeof child === "object" && child.t) {
      childrenStr += child.t.join("");
    } else if (child !== undefined && child !== null && child !== false && child !== true) {
      // Don't escape content of script and style tags
      if (tag === "script" || tag === "style") {
        childrenStr += String(child);
      } else {
        childrenStr += escape(String(child));
      }
    }
  };
  
  processChild(children);

  return { t: [`<${tag}${attrStr}>${childrenStr}</${tag}>`] };
}

export const jsxs = jsx;
export const jsxDEV = jsx;

export function Fragment(props: any) {
  return props.children;
}

