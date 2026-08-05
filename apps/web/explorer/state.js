import { DEFAULT_URL_STATE } from "./url-state.js";

export function createInitialState(urlState = {}) {
  return {
    ...DEFAULT_URL_STATE,
    ...urlState,
    runs: [],
    runInfo: null,
    manifest: null,
    metadata: null,
    payload: null,
    scene: null,
    selection: null,
    hover: null,
    status: "boot",
    statusDetail: "Finding compatible traced runs…",
    error: null,
    requestRevision: 0,
    committedRevision: 0,
    cameraIntent: "fit-scene",
    playing: false,
    tableFilter: "",
    tablePage: 0,
    motionReduced: globalThis.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false,
  };
}

export function reducer(state, action) {
  switch (action.type) {
    case "MERGE":
      return { ...state, ...action.patch };
    case "SET_RUN":
      return {
        ...state,
        run: action.run,
        runInfo: action.runInfo || null,
        manifest: null,
        metadata: null,
        payload: null,
        scene: null,
        selection: null,
        selected: action.preserveRequestedState ? state.selected : null,
        parent: action.preserveRequestedState ? state.parent : null,
        focus: action.preserveFocus ? state.focus : null,
        quarter: action.preserveRequestedState ? state.quarter : null,
        status: "loading-manifest",
        statusDetail: "Loading run capabilities…",
        error: null,
        requestRevision: state.requestRevision + 1,
        cameraIntent: "fit-scene",
        playing: false,
      };
    case "SET_QUARTER":
      return {
        ...state,
        quarter: action.quarter,
        status: "loading-quarter",
        statusDetail: `Loading recorded quarter ${action.quarter}…`,
        requestRevision: state.requestRevision + 1,
        cameraIntent: action.fit ? "fit-scene" : state.cameraIntent,
        error: null,
      };
    case "SET_ALTITUDE":
      return {
        ...state,
        altitude: action.altitude,
        selection: null,
        status: "loading-quarter",
        statusDetail: `Building ${action.altitude} view…`,
        requestRevision: state.requestRevision + 1,
        cameraIntent: "fit-scene",
        playing: false,
        error: null,
      };
    case "SET_FOCUS":
      return {
        ...state,
        focus: action.focus || null,
        selection: null,
        status: "loading-quarter",
        statusDetail: action.focus ? "Loading the selected actor's relationships…" : "Restoring economic context…",
        requestRevision: state.requestRevision + 1,
        cameraIntent: "fit-scene",
        playing: false,
        error: null,
      };
    case "SET_LAYERS":
      return {
        ...state,
        layers: [...new Set(action.layers)],
        selection: null,
        status: "loading-quarter",
        statusDetail: "Applying economic layer filters…",
        requestRevision: state.requestRevision + 1,
        error: null,
      };
    case "SET_COVERAGE":
      return {
        ...state,
        coverage: action.coverage,
        status: "loading-quarter",
        statusDetail: "Recomputing value coverage…",
        requestRevision: state.requestRevision + 1,
        error: null,
      };
    case "LOAD_READY":
      if (action.revision !== state.requestRevision) return state;
      return {
        ...state,
        ...action.patch,
        status: "ready",
        statusDetail: "",
        committedRevision: action.revision,
        error: null,
      };
    case "LOAD_ERROR":
      if (action.revision != null && action.revision !== state.requestRevision) return state;
      return {
        ...state,
        status: "error",
        statusDetail: action.message,
        error: action.error || new Error(action.message),
        playing: false,
      };
    case "SELECT":
      return { ...state, selection: action.selection || null };
    case "HOVER":
      return { ...state, hover: action.hover || null };
    case "CAMERA_COMMITTED":
      return { ...state, cameraIntent: null };
    case "SET_PLAYING":
      return { ...state, playing: Boolean(action.playing) && !state.motionReduced };
    default:
      return state;
  }
}

export function createStore(initialState, reduce = reducer) {
  let state = initialState;
  const listeners = new Set();
  return {
    getState: () => state,
    dispatch(action) {
      const next = reduce(state, action);
      if (next === state) return state;
      state = next;
      for (const listener of listeners) listener(state, action);
      return state;
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}
