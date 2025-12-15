import { JSX } from "solid-js";

export default function Application(props: { children: JSX.Element }) {
  return (
    <html>
      <head>
        <title>Lazuli Example</title>
        <meta charset="utf-8" />
        <script type="importmap">{`
        {
          "imports": {
            "solid-js": "https://esm.sh/solid-js@1.8.16?target=es2022",
            "solid-js/web": "https://esm.sh/solid-js@1.8.16/web?target=es2022",
            "solid-js/jsx-runtime": "https://esm.sh/solid-js@1.8.16/h/jsx-runtime?target=es2022"
          }
        }
        `}</script>
      </head>
      <body>
        <div id="root">{props.children}</div>
      </body>
    </html>
  );
}
