import { describe, expect, it } from "vitest";
import { parseConcernLocation } from "@/lib/location";
describe("optional concern locations", () => {
  it("accepts no pin, trims landmarks, and supports boundary coordinates", () => {
    expect(parseConcernLocation({})).toBeNull();
    expect(
      parseConcernLocation({
        latitude: null,
        longitude: null,
        locationNote: " ",
      }),
    ).toBeNull();
    expect(
      parseConcernLocation({
        latitude: -90,
        longitude: 180,
        locationNote: "  Landmark  ",
      }),
    ).toEqual({ latitude: -90, longitude: 180, locationNote: "Landmark" });
  });
  it.each([
    { latitude: 8 },
    { longitude: 125 },
    { latitude: NaN, longitude: 125 },
    { latitude: 8, longitude: Infinity },
    { latitude: 91, longitude: 125 },
    { latitude: 8, longitude: -181 },
    { latitude: "8", longitude: 125 },
    { locationNote: "No pin" },
    { latitude: 8, longitude: 125, locationNote: "x".repeat(301) },
    { locationNote: {} },
  ])("rejects invalid coordinates/landmarks %j", (input) =>
    expect(() => parseConcernLocation(input)).toThrow(),
  );
});
