import { JSX } from "solid-js";

export default function Application(props: { children: JSX.Element }) {
  return (
    <html>
      <head>
        <title>Lazuli Example</title>
        <meta charset="utf-8" />
      </head>
      <body>
        <div id="root">{props.children}</div>
      </body>
    </html>
  );
}
