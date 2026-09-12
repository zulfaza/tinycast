// Node's `events`. Its own module because the stream core builds on it and `node-shims` builds on
// the stream core, so leaving it there would close an import cycle.

export class EventEmitter {
  constructor() {
    this._events = new Map();
    this._maxListeners = 10;
  }
  _list(event) {
    if (!this._events.has(event)) this._events.set(event, []);
    return this._events.get(event);
  }
  on(event, listener) {
    this._list(event).push(listener);
    return this;
  }
  addListener(event, listener) {
    return this.on(event, listener);
  }
  prependListener(event, listener) {
    this._list(event).unshift(listener);
    return this;
  }
  once(event, listener) {
    const wrapper = (...args) => {
      this.off(event, wrapper);
      listener(...args);
    };
    wrapper.listener = listener;
    return this.on(event, wrapper);
  }
  off(event, listener) {
    const list = this._events.get(event);
    if (!list) return this;
    const index = list.findIndex((entry) => entry === listener || entry.listener === listener);
    if (index >= 0) list.splice(index, 1);
    return this;
  }
  removeListener(event, listener) {
    return this.off(event, listener);
  }
  removeAllListeners(event) {
    if (event === undefined) this._events.clear();
    else this._events.delete(event);
    return this;
  }
  emit(event, ...args) {
    const list = this._events.get(event);
    if (!list?.length) return false;
    for (const listener of list.slice()) listener.apply(this, args);
    return true;
  }
  listenerCount(event) {
    return this._events.get(event)?.length ?? 0;
  }
  listeners(event) {
    return (this._events.get(event) ?? []).slice();
  }
  eventNames() {
    return Array.from(this._events.keys());
  }
  setMaxListeners(count) {
    this._maxListeners = count;
    return this;
  }
  getMaxListeners() {
    return this._maxListeners;
  }
}

EventEmitter.EventEmitter = EventEmitter;
EventEmitter.defaultMaxListeners = 10;
EventEmitter.setMaxListeners = (count, ...targets) => {
  for (const target of targets) {
    if (typeof target?.setMaxListeners === "function") target.setMaxListeners(count);
    else if (target) target._maxListeners = count;
  }
};
EventEmitter.addAbortListener = (signal, listener) => {
  const abort = () => listener();
  if (signal.aborted) queueMicrotask(abort);
  else signal.addEventListener("abort", abort, { once: true });
  return {
    [Symbol.dispose]() {
      signal.removeEventListener("abort", abort);
    },
  };
};

function abortError(signal) {
  if (signal?.reason instanceof Error) return signal.reason;
  const error = new Error("The operation was aborted");
  error.name = "AbortError";
  return error;
}

EventEmitter.once = (emitter, event, options = {}) =>
  new Promise((resolve, reject) => {
    const cleanup = () => {
      emitter.off(event, receive);
      if (event !== "error") emitter.off("error", fail);
      options.signal?.removeEventListener("abort", abort);
    };
    const receive = (...args) => {
      cleanup();
      resolve(args);
    };
    const fail = (error) => {
      cleanup();
      reject(error);
    };
    const abort = () => {
      cleanup();
      reject(abortError(options.signal));
    };
    if (options.signal?.aborted) return abort();
    emitter.once(event, receive);
    if (event !== "error") emitter.once("error", fail);
    options.signal?.addEventListener("abort", abort, { once: true });
  });

EventEmitter.on = (emitter, event, options = {}) => {
  const queued = [];
  const waiting = [];
  let stopped = false;
  let failure;

  const cleanup = () => {
    emitter.off(event, receive);
    if (event !== "error") emitter.off("error", fail);
    options.signal?.removeEventListener("abort", abort);
  };
  const stop = (error) => {
    if (stopped) return;
    stopped = true;
    failure = error;
    cleanup();
    for (const waiter of waiting.splice(0)) {
      if (failure) waiter.reject(failure);
      else waiter.resolve({ value: undefined, done: true });
    }
  };
  const receive = (...args) => {
    const waiter = waiting.shift();
    if (waiter) waiter.resolve({ value: args, done: false });
    else queued.push(args);
  };
  const fail = (error) => stop(error);
  const abort = () => stop(abortError(options.signal));

  if (options.signal?.aborted) stop(abortError(options.signal));
  else {
    emitter.on(event, receive);
    if (event !== "error") emitter.on("error", fail);
    options.signal?.addEventListener("abort", abort, { once: true });
  }

  return {
    [Symbol.asyncIterator]() {
      return this;
    },
    next() {
      if (queued.length) return Promise.resolve({ value: queued.shift(), done: false });
      if (failure) return Promise.reject(failure);
      if (stopped) return Promise.resolve({ value: undefined, done: true });
      return new Promise((resolve, reject) => waiting.push({ resolve, reject }));
    },
    return() {
      stop();
      return Promise.resolve({ value: undefined, done: true });
    },
  };
};
