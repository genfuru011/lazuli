import { FC } from "hono/jsx";
import { timeStamp } from "node:console";

const Island: FC<{ path: string; component: any; data: any }> = (props) => {
  const id = "island-" + Math.random().toString(36).slice(2);
  const Component = props.component;
  const jsonProps = JSON.stringify(props.data);

  return (
    <>
      <div id={id}>
        <Component {...props.data} />
      </div>
      <script type="module" dangerouslySetInnerHTML={{ __html: `
        import { render } from "hono/jsx/dom";
        import { jsx } from "hono/jsx";
        import Component from "/assets/${props.path}.tsx";
        const el = document.getElementById("${id}");
        render(jsx(Component, ${jsonProps}), el);
      ` }} />
    </>
  );
};

export default Island;
