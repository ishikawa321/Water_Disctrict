"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { Map as LeafletMap, Marker } from "leaflet";
import { Crosshair, MapPin, MapPinned } from "lucide-react";
import "leaflet/dist/leaflet.css";
import {
  locationLabel,
  parseConcernLocation,
  type ConcernLocation,
} from "@/lib/location";
import type { Concern } from "@/lib/types";
import { Modal } from "./modal";
import { Feedback, Field } from "./ui";
type Point = Pick<ConcernLocation, "latitude" | "longitude">;

function MapSurface({
  point,
  readOnly = false,
  onSelect,
  onTileError,
}: {
  point: Point | null;
  readOnly?: boolean;
  onSelect: (point: Point) => void;
  onTileError: () => void;
}) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<LeafletMap | null>(null);
  const marker = useRef<Marker | null>(null);
  const initial = useRef(point);
  const [ready, setReady] = useState(false);
  const latitude = point?.latitude;
  const longitude = point?.longitude;
  useEffect(() => {
    let stopped = false;
    let instance: LeafletMap | undefined;
    let resize: ResizeObserver | undefined;
    void import("leaflet")
      .then((L) => {
        if (stopped || !container.current) return;
        const start = initial.current;
        const reduced = window.matchMedia(
          "(prefers-reduced-motion: reduce)",
        ).matches;
        instance = L.map(container.current, {
          minZoom: 3,
          maxZoom: 19,
          scrollWheelZoom: false,
          zoomAnimation: !reduced,
          fadeAnimation: !reduced,
        }).setView(
          start ? [start.latitude, start.longitude] : [7.7633, 125.0058],
          start ? 17 : 13,
        );
        map.current = instance;
        L.tileLayer(
          process.env.NEXT_PUBLIC_MAP_TILE_URL ||
            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          {
            maxZoom: 19,
            attribution:
              process.env.NEXT_PUBLIC_MAP_TILE_ATTRIBUTION ||
              '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors',
          },
        )
          .on("tileerror", onTileError)
          .addTo(instance);
        if (!readOnly)
          instance.on("click", (event) => {
            const wrapped = event.latlng.wrap();
            if (wrapped.lat >= -90 && wrapped.lat <= 90)
              onSelect({ latitude: wrapped.lat, longitude: wrapped.lng });
          });
        resize = new ResizeObserver(() => instance?.invalidateSize());
        resize.observe(container.current);
        setReady(true);
      })
      .catch(onTileError);
    return () => {
      stopped = true;
      resize?.disconnect();
      instance?.remove();
      map.current = null;
      marker.current = null;
    };
  }, [readOnly, onSelect, onTileError]);
  useEffect(() => {
    if (!ready || !map.current || latitude == null || longitude == null) return;
    let stopped = false;
    void import("leaflet").then((L) => {
      if (stopped || !map.current) return;
      const point = L.latLng(latitude, longitude);
      if (marker.current) marker.current.setLatLng(point);
      else {
        const pin = L.divIcon({
          className: "issue-pin",
          html: '<span aria-hidden="true">●</span>',
          iconSize: [26, 26],
          iconAnchor: [13, 13],
        });
        marker.current = L.marker(point, {
          icon: pin,
          title: "Selected issue location",
          alt: "Selected issue location",
        }).addTo(map.current);
      }
      map.current.panTo(point, { animate: false });
    });
    return () => {
      stopped = true;
    };
  }, [latitude, longitude, ready]);
  return (
    <>
      <div
        ref={container}
        className={`concern-map ${readOnly ? "read-only" : ""}`}
        role="region"
        aria-label={
          readOnly
            ? "Saved concern location map"
            : "Choose issue location on map"
        }
        tabIndex={0}
      />
      {!readOnly && (
        <button
          type="button"
          className="secondary map-center"
          disabled={!ready}
          onClick={() => {
            const center = map.current?.getCenter().wrap();
            if (center)
              onSelect({ latitude: center.lat, longitude: center.lng });
          }}
        >
          <MapPin size={16} />
          Place pin at map center
        </button>
      )}
    </>
  );
}

function LocationDialog({
  initial,
  readOnly = false,
  onConfirm,
  onClose,
}: {
  initial: ConcernLocation | null;
  readOnly?: boolean;
  onConfirm?: (location: ConcernLocation) => void;
  onClose: () => void;
}) {
  const [point, setPoint] = useState<Point | null>(initial);
  const [note, setNote] = useState(initial?.locationNote ?? "");
  const [latitude, setLatitude] = useState(
    initial ? String(initial.latitude) : "",
  );
  const [longitude, setLongitude] = useState(
    initial ? String(initial.longitude) : "",
  );
  const [error, setError] = useState<string | null>(null);
  const [locating, setLocating] = useState(false);
  const [gpsHint, setGpsHint] = useState(false);
  const [tileError, setTileError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const select = useCallback((point: Point) => {
    setPoint(point);
    setLatitude(String(point.latitude));
    setLongitude(String(point.longitude));
    setError(null);
  }, []);
  const tileFailed = useCallback(() => setTileError(true), []);
  function locate() {
    if (!window.isSecureContext || !navigator.geolocation) {
      setError(
        "Device location is unavailable. Choose a pin manually or enter coordinates.",
      );
      return;
    }
    setLocating(true);
    setError(null);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        select({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
        });
        setLocating(false);
        setGpsHint(true);
      },
      (failure) => {
        setLocating(false);
        setError(
          failure.code === 1
            ? "Location permission was denied. You can still choose a pin manually."
            : failure.code === 3
              ? "Location lookup timed out. You can still choose a pin manually."
              : "Device location is unavailable. Choose a pin manually.",
        );
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  }
  function useCoordinates() {
    try {
      if (!latitude.trim() || !longitude.trim())
        throw new Error("Enter both latitude and longitude.");
      const location = parseConcernLocation({
        latitude: Number(latitude),
        longitude: Number(longitude),
      });
      if (location) select(location);
    } catch (failure) {
      setError(
        failure instanceof Error ? failure.message : "Choose a valid location.",
      );
    }
  }
  function confirm() {
    try {
      if (!point)
        throw new Error("Choose a pin on the map or enter its coordinates.");
      const location = parseConcernLocation({ ...point, locationNote: note });
      if (location) onConfirm?.(location);
    } catch (failure) {
      setError(
        failure instanceof Error ? failure.message : "Choose a valid location.",
      );
    }
  }
  return (
    <Modal
      title={readOnly ? "Concern location" : "Choose location"}
      onClose={onClose}
      wide
    >
      <div className="stack">
        <p>
          {readOnly
            ? "Reported issue location. This saved pin is read-only."
            : "Tap the map to place a pin at the issue. You can also pan with the arrow keys and place a pin at the map center."}
        </p>
        <Feedback error={error} />
        {tileError && (
          <div className="feedback info" role="status">
            Map tiles could not load. Your selected pin is kept.
            <button
              type="button"
              className="text-button"
              onClick={() => {
                setTileError(false);
                setAttempt((value) => value + 1);
              }}
            >
              Retry map
            </button>
          </div>
        )}
        <MapSurface
          key={attempt}
          point={point}
          readOnly={readOnly}
          onSelect={select}
          onTileError={tileFailed}
        />
        {point && (
          <p className="coordinates" aria-live="polite">
            {point.latitude.toFixed(6)}, {point.longitude.toFixed(6)}
          </p>
        )}
        {readOnly ? (
          <>
            {note && <p className="prose">{note}</p>}
            <button type="button" className="secondary" onClick={onClose}>
              Close location
            </button>
          </>
        ) : (
          <>
            <button
              type="button"
              className="secondary"
              disabled={locating}
              onClick={locate}
            >
              <Crosshair size={17} />
              {locating ? "Finding location…" : "Use my location"}
            </button>
            {gpsHint && (
              <p role="status">
                Device location may be approximate. Confirm or adjust the pin
                before saving.
              </p>
            )}
            <details className="record-details">
              <summary>Enter coordinates manually</summary>
              <div className="form">
                <div className="form-row">
                  <Field label="Latitude">
                    <input
                      inputMode="decimal"
                      value={latitude}
                      onChange={(event) => setLatitude(event.target.value)}
                    />
                  </Field>
                  <Field label="Longitude">
                    <input
                      inputMode="decimal"
                      value={longitude}
                      onChange={(event) => setLongitude(event.target.value)}
                    />
                  </Field>
                </div>
                <button
                  className="secondary"
                  type="button"
                  onClick={useCoordinates}
                >
                  Use coordinates
                </button>
              </div>
            </details>
            <Field
              label="Landmark / location note (optional)"
              hint={`${note.length} / 300 characters`}
            >
              <textarea
                value={note}
                onChange={(event) => setNote(event.target.value)}
                maxLength={300}
                rows={2}
                placeholder="Nearby landmark or directions to the issue"
              />
            </Field>
            <small>
              The pin is saved with your concern only after you submit the
              report.
            </small>
            <div className="row wrap">
              <button
                className="primary"
                type="button"
                disabled={!point || locating}
                onClick={confirm}
              >
                Confirm location
              </button>
              <button className="secondary" type="button" onClick={onClose}>
                Cancel
              </button>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}

export function LocationField({
  value,
  onChange,
  disabled = false,
}: {
  value: ConcernLocation | null;
  onChange: (value: ConcernLocation | null) => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="location-field">
      <h3>
        <MapPin size={17} />
        Issue location (optional)
      </h3>
      {value ? (
        <>
          <p>{value.locationNote || "Selected issue location"}</p>
          <small className="coordinates">{locationLabel(value)}</small>
        </>
      ) : (
        <p>Choose the exact spot that needs attention.</p>
      )}
      <div className="row wrap">
        <button
          type="button"
          className="secondary"
          disabled={disabled}
          onClick={() => setOpen(true)}
        >
          <MapPinned size={16} />
          {value ? "Change location" : "Choose location"}
        </button>
        {value && (
          <button
            type="button"
            className="text-button"
            disabled={disabled}
            onClick={() => onChange(null)}
          >
            Remove location
          </button>
        )}
      </div>
      {open && (
        <LocationDialog
          initial={value}
          onClose={() => setOpen(false)}
          onConfirm={(location) => {
            onChange(location);
            setOpen(false);
          }}
        />
      )}
    </div>
  );
}

export function LocationDetails({ concern }: { concern: Concern }) {
  const [open, setOpen] = useState(false);
  let location: ConcernLocation | null = null;
  try {
    location = parseConcernLocation(concern);
  } catch {
    /* Historical invalid pairs are never shown as real coordinates. */
  }
  const supported =
    concern.latitude !== undefined && concern.longitude !== undefined;
  return (
    <div className="location-details">
      <h3>
        <MapPin size={17} />
        Reported issue location
      </h3>
      {location ? (
        <>
          <p>{location.locationNote || "Saved location pin"}</p>
          <p className="coordinates">{locationLabel(location)}</p>
          <button
            type="button"
            className="secondary"
            onClick={() => setOpen(true)}
          >
            View location
          </button>
          {open && (
            <LocationDialog
              initial={location}
              readOnly
              onClose={() => setOpen(false)}
            />
          )}
        </>
      ) : (
        <p>
          {supported
            ? "No location provided."
            : "Location details are not available from this office service yet."}
        </p>
      )}
    </div>
  );
}
