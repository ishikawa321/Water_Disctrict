"use client";
import {
  Children,
  cloneElement,
  isValidElement,
  useId,
  type ReactNode,
  type ReactElement,
} from "react";
type ControlProps = {
  children?: ReactNode;
  id?: string;
  "aria-describedby"?: string;
};
function associateControls(
  children: ReactNode,
  id: string,
  hintId?: string,
): ReactNode {
  return Children.map(children, (child) => {
    if (!isValidElement<ControlProps>(child)) return child;
    if (
      typeof child.type === "string" &&
      ["input", "select", "textarea"].includes(child.type)
    )
      return cloneElement(child, { id, "aria-describedby": hintId });
    if (child.props.children)
      return cloneElement(child as ReactElement<ControlProps>, {
        children: associateControls(child.props.children, id, hintId),
      });
    return child;
  });
}
export function Field({
  label,
  children,
  hint,
}: {
  label: string;
  children: ReactNode;
  hint?: string;
}) {
  const id = useId();
  const hintId = hint ? `${id}-hint` : undefined;
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {associateControls(children, id, hintId)}
      {hint && <small id={hintId}>{hint}</small>}
    </div>
  );
}
