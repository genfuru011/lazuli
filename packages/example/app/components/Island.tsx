import { createUniqueId } from "solid-js";
import { ssr } from "solid-js/web";

export default function Island(props: { path: string, component: any, data: any }) {
  const id = createUniqueId();
  const Component = props.component;
  
  // We need to serialize props safely
  const jsonProps = JSON.stringify(props.data);
  
  return (
    <>
      <div id={id}>
        <Component {...props.data} />
      </div>
      <script type="module">{`
        import { hydrate } from "https://esm.sh/solid-js@1.8.16/web";
        import h from "https://esm.sh/solid-js@1.8.16/h";
        import Component from "/assets/${props.path}.tsx";
        const el = document.getElementById("${id}");
        hydrate(() => h(Component, ${jsonProps}), el);
      `}</script>
    </>
  );
}
