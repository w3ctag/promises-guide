# Writing Promise-Using Specifications

## Abstract

A _promise_ is an object that represents the eventual result of a single asynchronous operation. They can be returned from asynchronous functions, thus allowing consumers to not only queue up callbacks to be called when the operation succeeds or fails, but also to manipulate the returned promise object, opening up a variety of possibilities.

Promises have been battle-tested in many JavaScript libraries, including as part of popular frameworks like Dojo, jQuery, YUI, Ember, Angular, WinJS, and others. This culminated in the [Promises/A+ community specification](http://promisesaplus.com/) which most libraries conformed to. Now, a standard `Promise` class is included [in the next version of ECMAScript](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise-objects), allowing web platform APIs to return promises for their asynchronous operations.

Promises are now the web platform's paradigm for all "one and done" asynchronous operations. Previously, specifications used a variety of mismatched mechanisms for such operations. Going forward, all asynchronous operations of this type should be specified to instead return promises, giving our platform a unified primitive for asynchronicity.

This document gives some guidance on how to write specifications that create, accept, or manipulate promises. It also includes a series of prose shorthands you can use in your specification to work with promises.

## When to Use Promises

### One-and-Done Operations

The primary use case for promises is returning them from a method that kicks off a single asynchronous operation. One should think of promise-returning functions as asynchronous functions, in contrast to normal synchronous functions; there is a very strong analogy here, and keeping it in mind makes such functions easier to write and reason about.

For example, normal synchronous functions can either return a value or throw an exception. Asynchronous functions will, analogously, return a promise, which can either be fulfilled with a value, or rejected with a reason. Just like a synchronous function that returns "nothing" (i.e. `undefined`), promises returned by asynchronous functions can be fulfilled with nothing (`undefined`); in this case the promise fulfillment simply signals completion of the asynchronous operation.

Examples of such asynchronous operations abound throughout web specifications:

- Asynchronous I/O operations: methods to read or write from a storage API could return a promise.
- Asynchronous network operations: methods to send or receive data over the network could return a promise.
- Long-running computations: methods that take a while to compute something could do the work on another thread, returning a promise for the result.
- User interface prompts: methods that ask the user for an answer could return a promise.

Previously, web specifications used a large variety of differing patterns for asynchronous operations. We've documented these in an appendix below, so you can get an idea of what is now considered legacy. Now that we have promises as a platform primitive, such approaches are no longer necessary.

### One-Time "Events"

Because promises can be subscribed to even after they've already been fulfilled or rejected, they can be very useful for a certain class of "event." When something only happens once, and authors often want to observe the status of it after it's already occurred, providing a promise that becomes fulfilled when that eventuality comes to pass gives a very convenient API.

The prototypical example of such an "event" is a loaded indicator: a resource such as an image, font, or even document, could provided a `loaded` property that is a promise that becomes fulfilled only when the resource has fully loaded (or becomes rejected if there's an error loading the resource). Then, authors can always queue up actions to be executed once the resource is ready by doing `resource.loaded.then(onLoaded, onFailure)`. This will work even if the resource was loaded already, queueing a microtask to execute `onLoaded` . This is in contrast to an event model, where if the author is not subscribed at the time the event fires, that information is lost.

### More General State Transitions

In certain cases, promises can be useful as a general mechanism for signaling state transitions. This usage is subtle, but can provide a very nice API for consumers when done correctly.

One can think of this pattern as a generalization of the one-time "events" use case. For example, take `<img>` elements. By resetting their `src` property, they can be re-loaded; that is, they can transition back from a loaded state to an unloaded state. Thus becoming loaded is not a one-time occasion: instead, the image actually consists of a state machine that moves back and forth between loaded and unloaded states. In such a scenario, it is still useful to give images a promise-returning `loaded` property, which will signal the next state transition to a loaded state (or be already fulfilled if the image is already in a loaded state). This property should return the same promise every time it is retrieved, until the image moves backward from the loaded state into the unloaded state. Once that occurs, a new promise is created, representing the _next_ transition to loaded.

There are many places in the platform where this can be useful, not only for resources which can transition to loaded, but e.g. for animations that can transition to finished, or expensive resources that can transition to disposed, or caches that can become unloaded.

A slight variant of this pattern occurs when your class contains a method that causes a state transition, and you want to indicate when that state transition completes. In that case you can return a promise from the method, instead of keeping it as a property on your object. The [streams API](https://github.com/whatwg/streams/) uses this variant for its `wait()` and `close()` methods. In general, methods should be used for actions, and properties for informational state transitions.

To close, we must caution against over-using this pattern. Not every state transition needs a corresponding promise-property. Indicators that it might be useful include:

- Authors are almost always interested in the _next_ instance of that state transition, and rarely need recurring notification every time it occurs. For example, rarely do authors care to know every time an image element is reloaded; usually they simply care about the initial load of the image, or possibly the next one that occurs after resetting its `src`.
- Authors are often interested in reacting to transitions that have already occurred. For example, authors often want to run some code once an image is loaded; if the image is already loaded, they want to run the code as soon as possible.

## When Not to Use Promises

Although promises are widely applicable to asynchronous operations of many sorts, there are still situations where they are not appropriate, even for asynchronicity.

### Recurring Events

Any event that can occur more than once is not a good candidate for the "one and done" model of promises. There is no single asynchronous operation for the promise to represent, but instead a series of events. Conventional `EventTarget` usage is just fine here.

### Streaming Data

If the amount of data involved is potentially large, and could be produced incrementally, promises are probably not the right solution. Instead, you'll want to use the under-development [streams API](https://github.com/whatwg/streams), which allows authors to process and compose data streams incrementally, without buffering the entire contents of the stream into memory.

Note that in some cases, you could provide a promise API alongside a streaming API, as a convenience for those cases when buffering all the data into memory is not a concern. But this would be a supporting, not primary, role.

## API Design Guidance

There are a few subtle aspects of using or accepting promises in your API. Here we attempt to address commonly-encountered questions and situations.

### Errors

#### Promise-Returning Functions Should Always Return Promises

Promise-returning functions should always return a promise, under all circumstances. Even if the result is available synchronously, or the inputs can be detected as invalid synchronously, this information needs to be communicated through a uniform channel so that a developer can be sure that by doing

```js
promiseFunction()
  .then(onSuccess)
  .catch(onFailure);
```

they are handling all successes and all errors.

In particular, promise-returning functions should never synchronously throw errors, since that would force duplicate error-handling logic on the consumer. Even argument validation errors are not OK. Instead, they should return rejected promises.

For WebIDL-based specs, this is taken care of automatically [by the WebIDL specification](http://heycam.github.io/webidl/#es-operations): any exceptions thrown by WebIDL operations, or by the WebIDL overload resolution algorithm itself, are automatically converted into rejections. For an example of how to do manual validation, see the `validatedDelay` example below.

#### Rejection Reasons Should Be `Error`s

Promise rejection reasons should always be instances of the ECMAScript `Error` type, just like synchronously-thrown exceptions should always be instances of `Error` as well.

In particular, for DOM or other web platform specs, this means you should never use `DOMError`, but instead use `DOMException`, which [per WebIDL](http://heycam.github.io/webidl/#es-exceptions) extends `Error`. You can of course also use one of the [built-in ECMAScript error types](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-error-objects).

#### Rejections Should Be Used for Exceptional Situations

What exactly you consider "exceptional" is up for debate, as always. But, you should always ask, before rejecting a promise: if this function was synchronous, would I expect a thrown exception under this circumstance? Or perhaps a failure value (like `null`, `false`, or `undefined`)? You should think about which behavior is more useful for consumers of your API. If you're not sure, pretend your API is synchronous and then think if your users would expect a thrown exception.

Good cases for rejections include:

- A failed I/O operation, like writing to storage or reading from the network.
- When it will be impossible to complete the requested task: for example if the operation is `accessUsersContacts()` and the user denies permission, then it should return a rejected promise.
- Any situation where something is internally broken while attempting an asynchronous operation: for example if the user passes in invalid data, or the environment is in an invalid state for this operation.

Bad uses of rejections include:

- When a value is asked for asynchronously and is not found: for example `asyncMap.get("key")` should return a promise for `undefined` when there is no entry for `"key"`, and similarly `asyncMap.has("key")` should return a promise for `false`. The absence of `"key"` would be unexceptional, and so a rejected promise would be a poor choice.
- When the operation is phrased as a question, and the answer is negative: for example if the operation is `hasPermissionToAccessUsersContacts()` and the user has denied permission, then it should return a promise fulfilled with `false`; it should not reject.

Cases where a judgement call will be necessary include:

- APIs that are more ambiguous about being a question versus a demand: for example `requestUsersContacts()` could return a promise fulfilled with `null` if the user denies permission, or it could return a promise rejected with an error stating that the user denied permission.

### Asynchronous Algorithms

#### Simply Resolve or Reject the Promise

Unlike in the old world of callbacks, there's no need to create separate callback types (e.g. in WebIDL) for your success and error cases. Instead, just resolve or reject your promise.

#### Note Asynchronous Steps Explicitly

It is important to note which steps in your algorithms will be run asynchronously, without blocking script execution. This instructs implementers as to which operations will need to use e.g. a background thread or asychronous I/O calls. And it helps authors to know the expected sequencing of _their_ operations with respect to those of your algorithm.

As an example, the following steps will give a promise that is resolved after _ms_ milliseconds:

1. Let _p_ be a new promise.
1. Run the following steps asynchronously:
   1. Wait _ms_ milliseconds.
   1. Resolve _p_ with **undefined**.
1. Return _p_.

If we had omitted the "Run the following steps asynchronously" heading, then the algorithm would have instructed implementers to block the main thread for _ms_ milliseconds, which is very bad! Whereas as written, this algorithm correctly describes a non-blocking wait.

#### Queue Tasks to Invoke User Code

Promises abstract away many of the details regarding notifying the user about async operations. For example, you can say "resolve _p_ with _x_" instead of e.g. "[queue a task](http://www.whatwg.org/specs/web-apps/current-work/#task-queue) to call the callback _cb_ with _x_," and it's understood that this will use the normal promise mechanisms. (Namely, the user can wait for fulfillment or rejection by passing callbacks to the promise's `then` method, which will call those callbacks in the next microtask.) So in most cases, you will not need to explicitly queue tasks inside your promise-based asynchronous algorithms.

However, in cases where you need to interface with user code in more ways than can be mediated via the promise, you'll still need to queue a task. For example, you may want to fire an event, which can call into user event handlers. Or you may need to perform a structured clone operation, which [can trigger getters](http://lists.w3.org/Archives/Public/public-webcrypto/2014Mar/0141.html). If these things must be done inside the asynchronous portion of your algorithm, you need to specify that they are done via a queued task, and with a specific task queue. This nails down the exact time such user-observable operations happen both in relation to other queued tasks, and to the microtask queue used by promises.

As an example, the following steps will return a promise resolved after _ms_ milliseconds, but also fire an event named `timerfinished` on `window`:

1. Let _p_ be a new promise.
1. Run the following steps asynchronously:
   1. Wait _ms_ milliseconds.
   1. Resolve _p_ with **undefined**.
   1. [Queue a task](http://www.whatwg.org/specs/web-apps/current-work/multipage/webappapis.html#queue-a-task) to [fire an event](http://dom.spec.whatwg.org/#concept-event-fire) named `timerfinished` at the [browsing context](https://w3c.github.io/screen-orientation/#dfn-browsing-context) [active document](https://w3c.github.io/screen-orientation/#dfn-active-document)'s [Window](https://w3c.github.io/screen-orientation/#dfn-window) object.
1. Return _p_.


### Accepting Promises

#### Promise Arguments Should Be Resolved

In general, when an argument is expected to be a promise, you should also allow thenables and non-promise values by *resolving* the argument to a promise before using it. You should *never* do a type-detection on the incoming value, or overload between promises and other values, or put promises in a union type.

In WebIDL-using specs, this is automatically taken care of by the [WebIDL promise type](http://heycam.github.io/webidl/#es-promise). To see what it means in JavaScript, consider the following function, which adds a delay of `ms` milliseconds to a promise:

```js
function addDelay(promise, ms) {
    return Promise.resolve(promise).then(v =>
        new Promise(resolve =>
            setTimeout(() => resolve(v), ms);
        );
    );
}

var p1 = addDelay(doAsyncOperation(), 500);
var p2 = addDelay("value", 1000);
```

In this example, `p1` will be fulfilled 500 ms after the promise returned by `doAsyncOperation()` fulfills, with that operation's value. (Or `p1` will reject as soon as that promise rejects.) And, since we resolve the incoming argument to a promise, the function can also work when you pass it the string `"value"`: `p2` will be fulfilled with `"value"` after 1000 ms. In this way, we essentially treat it as an immediately-fulfilled promise for that value.

#### User-Supplied Promise-Returning Functions Should Be "Promise-Called"

If the user supplies you with a function that you expect to return a promise, you should also allow it to return a thenable or non-promise value, or even throw an exception, and treat all these cases as if they had returned an analogous promise. We can encapsulate this process in an operation called "promise-calling" the supplied function. This allows us to have the same reaction to synchronous forms of success and failure that we would to asynchronous forms.

In JavaScript, you might express promise-calling this way:

```js
function promiseCall(func, ...args) {
    try {
        return Promise.resolve(func(...args));
    } catch (e) {
        return Promise.reject(e);
    }
}
```

See the `resource.open` example below for further discussion of how and why this should be used.

## Shorthand Phrases

_NOTE: this section should move to WebIDL, where it belongs. See [#10](https://github.com/w3ctag/promises-guide/issues/10)._

When writing such specifications, it's convenient to be able to refer to common promise operations concisely. We define here a set of shorthands that allow you to do so.

### Creating Promises

**"A new promise"** gives a new, initialized-but-unresolved promise object to manipulate further. It is equivalent to calling `new Promise((resolve, reject) => { ... })`, using the initial value of [the `Promise` constructor](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise-constructor). Here `...` stands in for code that saves the value of `resolve` and `reject` for later use by the shorthands under "manipulating promises."

**"A promise resolved with _x_"** or **"_x_ resolved as a promise"** is shorthand for the result of `Promise.resolve(x)`, using the initial value of [`Promise.resolve`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.resolve).

**"A promise rejected with _r_"** is shorthand for the result of `Promise.reject(r)`, using the initial value of [`Promise.reject`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.reject).

### Manipulating Promises

**"Resolve _p_ with _x_"** is shorthand for calling a previously-stored [`resolve` function](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise-resolve-functions) from creating `p`, with argument `x`.

**"Reject _p_ with _r_"** is shorthand for calling a previously-stored [`reject` function](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise-reject-functions) from creating `p`, with argument `r`.

### Reacting to Promises

**Upon fulfillment of _p_ with value _v_** is shorthand saying that the successive nested steps should be executed inside a function `onFulfilled` that is passed to `p.then(onFulfilled)`, using the initial value of `Promise.prototype.then`. The steps then have access to `onFulfilled`'s argument as _v_.

**Upon rejection of _p_ with reason _r_** is shorthand saying that the successive nested steps should be executed inside a function `onRejected` that is passed to `p.then(undefined, onRejected)`, using the initial value of `Promise.prototype.then`. The steps then have access to `onRejected`'s argument as _r_.

### Promise-Calling

The result of **promise-calling _f_(..._args_)** is:

- If the call returns a value _v_, the result of resolving _v_ to a promise.
- If the call throws an exception _e_, a promise rejected with _e_.

## Examples

### delay( ms )

`delay` is a function that returns a promise that will be fulfilled in _ms_ milliseconds. It illustrates how simply you can resolve a promise, with one line of prose.

1. Let _ms_ be ToNumber(_ms_).
1. If _ms_ is **NaN**, let _ms_ be **+0**; otherwise let _ms_ be the maximum of _ms_ and **+0**.
1. Let _p_ be a new promise.
1. Run the following steps asynchronously:
   1. Wait _ms_ milliseconds.
   1. Resolve _p_ with **undefined**.
1. Return _p_.

The equivalent function in JavaScript would be

```js
function delay(ms) {
    ms = Number(ms);
    ms = Number.isNaN(ms) ? +0 : Math.max(ms, +0);
    return new Promise(resolve => setTimeout(resolve, ms));
}
```

or, in a more one-to-one correspondence with the specified steps,

```js
function delay(ms) {
    // Steps 1, 2
    ms = Number(ms);
    ms = Number.isNaN(ms) ? +0 : Math.max(ms, +0);

    // Step 3
    let resolve;
    const p = new Promise(r => { resolve = r });

    // Step 4
    setTimeout(() => resolve(undefined), ms);

    // Step 5
    return p;
}
```

### validatedDelay( ms )

The `validatedDelay` function is much like the `delay` function, except it will validate its arguments. This shows how to use rejected promises to signal immediate failure before even starting any asynchronous operations.

1. Let _ms_ be ToNumber(_ms_).
1. If _ms_ is **NaN**, return a promise rejected with a **TypeError**.
1. If _ms_ is less than zero, return a promise rejected with a **RangeError**.
1. Let _p_ be a new promise.
1. Run the following steps asynchronously:
   1. Wait _ms_ milliseconds.
   1. Resolve _p_ with **undefined**.
1. Return _p_.

The equivalent function in JavaScript would be

```js
function delay(ms) {
    ms = Number(ms);

    if (Number.isNaN(ms)) {
        return Promise.reject(new TypeError("Not a number."));
    }
    if (ms < 0) {
        return Promise.reject(new RangeError("ms must be at least zero."));
    }

    return new Promise(resolve => setTimeout(resolve, ms));
}
```

### addDelay( promise, ms )

`addDelay` is a function that adds an extra _ms_ milliseconds of delay between _promise_ settling and the returned promise settling. Notice how it resolves the incoming argument to a promise, so that you could pass it a non-promise value or a thenable.

1. Let _ms_ be ToNumber(_ms_).
1. If _ms_ is **NaN**, let _ms_ be **+0**; otherwise let _ms_ be the maximum of _ms_ and **+0**.
1. Let _p_ be a new promise.
1. Let _resolvedToPromise_ be the result of resolving _promise_ to a promise.
1. Upon fulfillment of _promise_ with value _v_, perform the following steps asynchronously:
    1. Wait _ms_ milliseconds.
    1. Resolve _p_ with _v_.
1. Upon rejection of _promise_ with reason _r_, perform the following steps asynchronously:
    1. Wait _ms_ milliseconds.
    1. Reject _p_ with _r_.
1. Return _p_.

The equivalent function in JavaScript would be

```js
function addDelay(promise, ms) {
    ms = Number(ms);
    ms = Number.isNaN(ms) ? +0 : Math.max(ms, +0);

    let resolve, reject;
    const p = new Promise((r, rr) => { resolve = r; reject = rr; });

    const resolvedToPromise = Promise.resolve(promise);
    resolvedToPromise.then(
        v => setTimeout(() => resolve(v), ms),
        r => setTimeout(() => reject(r), ms)
    );

    return p;
}
```

### resource.open ( resourcePath, openingOperation )

`resource.open` is a method that executes the passed function _openingOperation_ to do most of its work, but then updates the `resource`'s properties to reflect the result of this operation. It is a simplified version of some of the techniques used in the streams specification. The method is meant to illustrate how and why you might promise-call another function.

1. Let _resourcePath_ be ToString(_resourcePath_).
1. Promise-call _openingOperation_(_resourcePath_):
    1. Upon fulfillment, set `this.status` to `"opened"`.
    1. Upon rejection with reason _r_, set `this.status` to `"errored"` and `this.error` to _r_.

The equivalent function in JavaScript would be

```js
resource.open = function (resourcePath, openingOperation) {
    resourcePath = String(resourcePath);

    promiseCall(openingOperation, resourcePath).then(
        v => {
            this.status = "opened";
        },
        r => {
            this.status = "errored";
            this.error = r;
        }
    );
};
```

using the `promiseCall` function defined above. If we had instead just called `openingOperation`, i.e. done `openingOperation(resourcePath)` directly, then code like

```js
resource.open(synchronouslyOpenTheResource);
```

would fail. It would not return a promise, so calling `then` on the return value would fail. Even if we accounted for that, what if `synchronouslyOpenTheResource` threw an error? We would want that to result in an `"errored"` status, but without promise-calling, that would not be the case: the error would simply cause `resource.open` to exit. So you can see that promise-calling is quite helpful here.

### environment.ready

`environment.ready` is a property that signals when some part of some environment becomes "ready," e.g. a DOM document. It illustrates how to appeal to environmental asynchrony.

1. Let `Environment.ready` be a new promise.
1. Asynchronously wait for one of the following to become true:
    1. When/if the environment becomes ready, resolve `Environment.ready` with **undefined**.
    1. When/if the environment fails to load, reject `Environment.ready` with an **Error** instance explaining the load failure.

### addBookmark ( )

`addBookmark` is a function that requests that the user add the current web page as a bookmark. It's drawn from some iterative design work in [#85](https://github.com/domenic/promises-unwrapping/issues/85) and illustrates a more real-world scenario of appealing to environmental asynchrony, as well as immediate rejections.

1. If this method was not invoked as a result of explicit user action, return a promise rejected with a new `DOMException` whose name is `"SecurityError"`.
1. If the document's mode of operation is standalone, return a promise rejected with a new `DOMException` whose name is `"NotSupported"`.
1. Let _promise_ be a new promise.
1. Let _info_ be the result of getting a web application's metadata.
1. Run the following steps asynchronously:
    1. Using _info_, and in a manner that is user-agent specific, allow the end user to make a choice as to whether they want to add the bookmark.
        1. If the end-user aborts the request to add the bookmark (e.g., they hit escape, or press a "cancel" button), reject _promise_ with a new `DOMException` whose name is `"AbortError"`.
        1. Otherwise, resolve _promise_ with **undefined**.
1. Return _promise_.

## WebIDL and Promises

[WebIDL](http://heycam.github.io/webidl/) provides a [`Promise<T>`](http://heycam.github.io/webidl/#es-promise) type which can be used when writing specifications that expose their API through WebIDL. We summarize the impact of `Promise<T>` here for easy reference.

### `Promise<T>` Return Values

Like all WebIDL return values, declaring a return value of type `Promise<T>` has no impact on the algorithm's actual return steps. It is simply a form of documentation, and if you return something that is not a promise or is a promise with a fulfillment value that is not of WebIDL-type `T`, then you have written incorrect documentation into your spec.

However, declaring that your method or accessor returns a promise does have one important impact: it ensures that any exceptions that it would otherwise throw, e.g. as a result of failed type conversions, are caught and turned into rejected promises. (See the ["Operations" section](http://heycam.github.io/webidl/#es-operations), "If _O_ has a return type that is a promise type …", and similar phrases scattered throughout the document.) This automatically takes care of the "Promise-Returning Functions Should Always Return Promises" advice from above, at least for exceptions.

### `Promise<T>` Parameters

When a parameter of a WebIDL method is declared as `Promise<T>`, it will automatically resolve any arguments passed in that position. This will take care of the "Promise Arguments Should Be Resolved" advice above.

If you have a WebIDL `Promise<T>` argument, you can use the WebIDL ["perform some steps once a promise is settled"](http://heycam.github.io/webidl/#dfn-perform-steps-once-promise-is-settled) algorithm. This is much like our "upon fulfillment …" and "upon rejection …" shorthand phrases above, but it will add an additional step of converting the promise's fulfillment value to the WebIDL type `T` before running any upon-fulfillment steps. Additionally it causes your algorithm to return a promise derived from running those steps. If the type conversion fails, your algorithm will return a promise rejected with the error causing that failure.

Note that the `T` here refers to a WebIDL type *for the fulfillment value*. Furthermore, it only has impact if you use the WebIDL "perform some steps …" algorithm, and not if you use the promise in other ways (such as passing it along to another function). If that is not relevant, we advise using `Promise<any>` for parameters.

As a consequence of the resolution behavior, `Promise<T>` parameters cannot be overloaded with any other parameters. For example, you cannot do:

```webidl
// INVALID WEBIDL
void f(Promise<DOMString> x);
void f(DOMString y);
```

### User Functions Returning Promises

In WebIDL, you consume JavaScript functions by declaring them as WebIDL [callback functions](http://heycam.github.io/webidl/#dfn-callback-function) (or, in rare cases, via [callback interfaces](http://heycam.github.io/webidl/#dfn-callback-interface)) and later [invoking them](http://heycam.github.io/webidl/#es-invoking-callback-functions) with a list of WebIDL values.

If you use WebIDL's mechanisms for calling JavaScript functions, the invocation algorithm will automatically resolve return values and convert thrown exceptions into rejected promises. This automatically takes care of the "User-Supplied Promise-Returning Functions Should Be 'Promise-Called'" advice from above.

### Examples

```webidl
// Promise-returning methods

interface ProtectedResource {
  Promise<void> requestAccess();
  ...
};

interface Quoter {
  Promise<DOMString> getInterestingQuote();
}
```

```webidl
// Promise-returning properties

interface StateMachine {
  readonly attribute Promise<void> loaded;

  Promise<void> load();
}
```

```webidl
// Promise-accepting methods

interface Waiter {
  void waitUntil(Promise<any> promise);
}
```

```webidl
// Promise-returning user functions

callback Promise<DOMString> ResourceLoader();

interface ResourceUser {
  void loadAndUseResource(ResourceLoader loader);
};
```

## Referencing Promises

When writing a spec that references promises, the correct form is something like the following:

> Promise objects are defined in [ECMASCRIPT]

With an entry in your references section that looks something like:

> **[ECMASCRIPT]** [ECMA-262 ECMAScript Language Specification, Edition 6](http://people.mozilla.org/~jorendorff/es6-draft.html). Draft. URL: http://people.mozilla.org/~jorendorff/es6-draft.html

Promises previously appeared in the DOM specification, but have been moved in to the ECMAScript language; it is no longer correct to reference the DOM specification. Relatedly, ECMAScript promises were for a while drafted at [domenic/promises-unwrapping](https://github.com/domenic/promises-unwrapping), but have since progressed into the official ECMAScript drafts; domenic/promises-unwrapping should not be used as a normative reference.

## Appendix: Legacy APIs for Asynchronicity

Many web platform APIs were written before the advent of promises, and thus came up with their own ad-hoc ways of signaling asynchronous operation completion or failure. These include:

- IndexedDB returning [`IDBRequest`](http://www.w3.org/TR/IndexedDB/#request-api) objects, with their `onsuccess` and `onerror` events
- The File API's [methods](http://www.w3.org/TR/file-system-api/#methods) taking various `successCallback` and `errorCallback` parameters
- The Notifications API's [`requestPermission`](http://notifications.spec.whatwg.org/#dom-notification-requestpermission) method, which calls its callback with `"granted"` or `"denied"`
- The Fullscreen API's [`requestFullscreen`](http://fullscreen.spec.whatwg.org/#dom-element-requestfullscreen) method, which triggers `onfullscreenchange` or `onfullscreenerror` events on the `document` object that must be listened to in order to detect success or failure.
- XMLHttpRequest's [`send`](http://xhr.spec.whatwg.org/#the-send%28%29-method) method, which triggers `onreadystatechange` multiple times and updates properties of the object with status information which must be consulted in order to accurately detect success or failure of the ultimate state transition

If you find yourself doing something even remotely similar to these, stop, and instead use promises.
