export type ConcernLocation = {
  latitude: number;
  longitude: number;
  locationNote: string;
};

export function parseConcernLocation(input: {
  latitude?: unknown;
  longitude?: unknown;
  locationNote?: unknown;
}): ConcernLocation | null {
  const { latitude, longitude, locationNote } = input;
  if (locationNote != null && typeof locationNote !== "string")
    throw new Error("Enter a valid location landmark.");
  const note = typeof locationNote === "string" ? locationNote.trim() : "";
  if (note.length > 300)
    throw new Error("The location landmark must be at most 300 characters.");
  if (latitude == null && longitude == null) {
    if (note)
      throw new Error("Choose a location pin before adding a landmark.");
    return null;
  }
  if (
    typeof latitude !== "number" ||
    typeof longitude !== "number" ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  )
    throw new Error("Choose a valid latitude and longitude together.");
  return { latitude, longitude, locationNote: note };
}

export function locationLabel(location: ConcernLocation) {
  return `${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)}`;
}
