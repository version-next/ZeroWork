import { describe, expect, test } from "bun:test";
import { selectMorphPresentation } from "./glass-motion-compare";

describe("original morph presentation evidence",()=>{
  const target={x:200,y:160,w:240,h:160};
  const moving={x:180,y:184,w:280,h:112};
  const frame=(display_time:number,rect=target)=>({display_time,rect});
  const select=(frames:ReturnType<typeof frame>[],relative:number,nativeRect=target,endTime=11)=>
    selectMorphPresentation(frames,relative,10,endTime,nativeRect,target,33.4,2);

  test("settled endpoint can remain on screen without new capture frames",()=>{
    const original=frame(10.30),frames=[frame(10.10,moving),original];
    const selected=select(frames,.44);
    expect(selected?.frame).toBe(original);
    expect(selected?.held).toBe(true);
    expect(selected?.frame.display_time).toBe(10.30);
    expect(selected?.visibleInterval).toEqual([10.30,11]);
    expect(frames).toHaveLength(2);
  });

  test("an old moving pose cannot be borrowed outside the presentation window",()=>{
    expect(select([frame(10.10,moving)],.30,moving)).toBeUndefined();
    expect(select([frame(10.10,moving)],.44,target)).toBeUndefined();
  });

  test("a frame stops being held when replaced",()=>{
    expect(select([frame(10.10),frame(10.20,moving)],.44)).toBeUndefined();
  });

  test("held evidence cannot extend beyond capture or before first presentation",()=>{
    expect(select([frame(10.30)],.44,target,10.40)).toBeUndefined();
    expect(select([frame(10.30)],.10)).toBeUndefined();
  });

  test("moving frames still use the unchanged 33.4 ms window",()=>{
    const original=frame(10.20,moving);
    expect(select([original],.2333,moving)?.frame).toBe(original);
    expect(select([original],.2333,moving)?.held).toBe(false);
    expect(select([original],.2335,moving)).toBeUndefined();
  });

  test("equal maximum edge error prefers the closer four-edge geometry",()=>{
    const worse=frame(10.20,{x:179,y:183,w:282,h:114});
    const closer=frame(10.225,{x:179,y:184,w:281,h:112});
    expect(select([worse,closer],.20,moving)?.frame).toBe(closer);
  });

  test("equal four-edge geometry prefers the closer presentation time",()=>{
    const early=frame(10.17,moving),nearby=frame(10.199,moving);
    expect(select([early,nearby],.20,moving)?.frame).toBe(nearby);
  });
});
