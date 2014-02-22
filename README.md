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

Previously, web specifications did things like

- IndexedDB returning [`IDBRequest`](http://www.w3.org/TR/IndexedDB/#request-api) objects, with their `onsuccess` and `onerror` events
- The File API's [methods](http://www.w3.org/TR/file-system-api/#methods) taking various `successCallback` and `errorCallback` parameters
- The Notifications API's [`requestPermission`](http://notifications.spec.whatwg.org/#dom-notification-requestpermission) method, which calls its callback with `"granted"` or `"denied"`
- The Fullscreen API's [`requestFullscreen`](http://fullscreen.spec.whatwg.org/#dom-element-requestfullscreen) method, which triggers `onfullscreenchange` or `onfullscreenerror` events on the `document` object that must be listened to in order to detect success or failure.
- XMLHttpRequest's [`send`](http://xhr.spec.whatwg.org/#the-send%28%29-method) method, which triggers `onreadystatechange` multiple times and updates properties of the object with status information which must be consulted in order to accurately detect success or failure of the ultimate state transition

Now that we have promises as a platform primitive, such approaches are no longer necessary.

### One-Time "Events"

Because promises can be subscribed to even after they've already been fulfilled or rejected, they can be very useful for a certain class of "event." When something only happens once, and authors often want to observe the status of it after it's already occurred, providing a promise that becomes fulfilled when that eventuality comes to pass gives a very convenient API.

The prototypical example of such an "event" is a loaded indicator: a resource such as an image, font, or even document, could provided a `ready` property that is a promise that becomes fulfilled only when the resource has fully loaded (or becomes rejected if there's an error loading the resource). Then, authors can always queue up actions to be executed once the resource is ready by doing `resource.ready.then(onReady, onFailure)`—even if the resource was loaded already. This is in contrast to an event model, where if the author is not subscribed at the time the event fires, that information is lost.

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

#### Promise-Returning Functions Should Never Throw

Promise-returning functions should never synchronously throw errors, since that would force duplicate error-handling logic on the consumer. Even argument validation errors are not OK. Instead, they should return rejected promises.

For WebIDL-based specs, this is taken care of automatically [by the WebIDL specification](http://heycam.github.io/webidl/#es-operations): any exceptions thrown by WebIDL operations, or by the WebIDL overload resolution algorithm itself, are automatically converted into rejections.

#### Rejection Reasons Should Be `Error`s

Promise rejection reasons should always be instances of the ECMAScript `Error` type, just like synchronously-thrown exceptions should always be instances of `Error` as well.

In particular, for DOM or other web platform specs, this means you should never use `DOMError`, but instead use `DOMException`, which [per WebIDL](http://heycam.github.io/webidl/#es-exceptions) extends `Error`. You can of course also use one of the [built-in ECMAScript error types](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-error-objects).

#### Rejections Should Be Used for Exceptional Situations

What exactly you consider "exceptional" is up for debate, as always. But, you should always ask, before rejecting a promise: if this function was synchronous, would I expect a thrown exception under this circumstance? Or perhaps a failure value (like `null` or `false`)?

For example, perhaps a user denying permission to use an API shouldn't be considered exceptional. Or perhaps it should! Just think about which behavior is more useful for consumers of your API, and if you're not sure, pretend your API is synchronous and then think if your users would want a thrown exception or not.

### Asynchronous Algorithms

_NOTE: This section has some issues; see [#7](https://github.com/w3ctag/promises-guide/issues/7)._

#### Maintain a Normal Control Flow

An antipattern that has been prevalent in async web specifications has been returning a value, then "continue running these steps asynchronously." This is hard to deal with for readers, because JavaScript doesn't let you do anything after returning from a function! Use promises to simplify your control flow into a normal linear sequence of steps:

- First, create the promise
- Then, describe how you'll perform the async operation—these are often "magic," e.g. asking for user input or appealing to the network stack. Say that if the operation succeeds, you'll resolve the promise, possibly with an appropriate value, and that if it fails, you'll reject it with an appropriate error.
- Finally, return the created promise.

#### Do Not Queue Needless Tasks

Sometimes specs explicitly [queue a task](http://www.whatwg.org/specs/web-apps/current-work/#task-queue) to perform async work. This is never necessary with promises! Promises ensure all invariants you would otherwise gain by doing this. Instead, just appeal to environmental asynchrony (like user input or the network stack), and from there resolve the promise.

#### No Need to Create Callbacks

Another guideline geared toward WebIDL-based specs. Unlike in the old world of callbacks, there's no need to create separate callback types for your success and error cases. Instead, just use the verbiage above. Create _promise_ as one of your first steps, using "let _promise_ be a new promise," then later, when it's time to resolve or reject it, say e.g. "resolve _promise_ with _value_" or "reject _promise_ with a new DOMException whose name is `"AbortError"`."

### Accepting Promises

#### Promise Arguments Should Be Cast

In general, when an argument is expected to be a promise, you should also allow thenables and non-promise values by *casting* the argument to a promise before using it. You should *never* do a type-detection on the incoming value, or overload between promises and other values, or put promises in a union type.

In WebIDL-using specs, this is automatically taken care of by the [WebIDL promise type](http://heycam.github.io/webidl/#es-promise). To see what it means in JavaScript, consider the following function, which adds a delay of `ms` milliseconds to a promise:

```js
function addDelay(promise, ms) {
    return Promise.cast(promise).then(v =>
        new Promise(resolve =>
            setTimeout(() => resolve(v), ms);
        );
    );
}

var p1 = addDelay(doAsyncOperation(), 500);
var p2 = addDelay("value", 1000);
```

In this example, `p1` will be fulfilled 500 ms after the promise returned by `doAsyncOperation()` fulfills, with that operation's value. (Or `p1` will reject as soon as that promise rejects.) And, since we cast the incoming argument to a promise, the function can also work when you pass it the string `"value"`: `p2` will be fulfilled with `"value"` after 1000 ms. That is, we "cast" the incoming string into a promise, essentially treating it as an immediately-fulfilled promise for that value.

#### User-Supplied Promise-Returning Functions Should Be "Promise-Called"

If the user supplies you with a function that you expect to return a promise, you should also allow it to return a thenable or non-promise value, or even throw an exception, and treat all these cases as if they had returned an analogous promise. We can encapsulate this process in an operation called "promise-calling" the supplied function. This allows us to have the same reaction to synchronous forms of success and failure that we would to asynchronous forms.

In JavaScript, you might express promise-calling this way:

```js
function promiseCall(func, ...args) {
    try {
        return Promise.cast(func(...args));
    } catch (e) {
        return Promise.reject(e);
    }
}
```

See the `resource.open` example below for further discussion of how and why this should be used.

## Shorthand Phrases

When writing such specifications, it's convenient to be able to refer to common promise operations concisely. We define here a set of shorthands that allow you to do so.

### Creating Promises

**"A new promise"** gives a new, initialized-but-unresolved promise object to manipulate further. It is equivalent to calling `new Promise((resolve, reject) => { ... })`, using the initial value of [the `Promise` constructor](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise-constructor). Here `...` stands in for code that saves the value of `resolve` and `reject` for later use by the shorthands under "manipulating promises."

**"A promise resolved with _x_"** is shorthand for the result of `Promise.resolve(x)`, using the initial value of [`Promise.resolve`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.resolve).

**"A promise rejected with _r_"** is shorthand for the result of `Promise.reject(r)`, using the initial value of [`Promise.reject`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.reject).

**"_x_ cast to a promise"** is shorthand for the result of `Promise.cast(x)`, using the initial value of [`Promise.cast`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.cast).

### Manipulating Promises

**"Resolve _p_ with _x_"** is shorthand for calling a previously-stored [`resolve` function](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise-resolve-functions) from creating `p`, with argument `x`.

**"Reject _p_ with _r_"** is shorthand for calling a previously-stored [`reject` function](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise-reject-functions) from creating `p`, with argument `r`.

### Reacting to Promises

**"Transforming _p_ with _onFulfilled_ and _onRejected_"** is shorthand for the result of calling `p.then(onFulfilled, onRejected)`, using the initial value of [`Promise.prototype.then`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.prototype.then).

**Upon fulfillment of _p_ with value _v_** is shorthand saying that the successive nested steps should be executed inside a function `onFulfilled` that is passed to `p.then(onFulfilled)`, using the initial value of `Promise.prototype.then`. The steps then have access to `onFulfilled`'s argument as _v_.

**Upon rejection of _p_ with reason _r_** is shorthand saying that the successive nested steps should be executed inside a function `onRejected` that is passed to `p.then(undefined, onRejected)`, using the initial value of `Promise.prototype.then`. The steps then have access to `onRejected`'s argument as _r_.

### Aggregating Promises

**"Racing _p1_, _p2_, _p3_, …"** is shorthand for the result of `Promise.race([p1, p2, p3, …])`, using the initial value of [`Promise.race`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.race).

**"Racing the elements of _iterable_"** is shorthand for the result of `Promise.race(iterable)`, using the initial value of [`Promise.race`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.race).

**"Waiting for all of _p1_, _p2_, _p3_, …"** is shorthand for the result of `Promise.all([p1, p2, p3, …])`, using the initial value of [`Promise.all`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.all).

**"Waiting for all of the elements of _iterable_"** is shorthand for the result of `Promise.all(iterable)`, using the initial value of [`Promise.all`](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise.all).

### Promise-Calling

The result of **promise-calling _f_(..._args_)** is:

- If the call returns a value _v_, the result of casting _v_ to a promise.
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

### environment.ready

environment.ready is a property that signals when some part of some environment becomes "ready," e.g. a DOM document. Notice how it appeals to environmental asynchrony.

1. Let Environment.ready be a new promise.
1. When/if the environment becomes ready, resolve Environment.ready with **undefined**.
1. When/if the environment fails to load, reject Environment.ready with an **Error** instance explaining the load failure.

### addDelay( promise, ms )

`addDelay` is a function that adds an extra _ms_ milliseconds of delay between _promise_ settling and the returned promise settling. Notice how it casts the incoming argument to a promise, so that you could pass it a non-promise value or a thenable.

1. Let _p_ be a new promise.
1. Let onFulfilled(_v_) be a function that waits _ms_ milliseconds, then resolves _p_ with _v_.
1. Let onRejected(_r_) be a function that waits _ms_ milliseconds, then rejects _p_ with _r_.
1. Let _castToPromise_ be the result of casting _promise_ to a promise.
1. Transform _castToPromise_ with _onFulfilled_ and _onRejected_.
1. Return _p_.

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

### addBookmark ( )

`addBookmark` is a function that requests that the user add the current web page as a bookmark. It's drawn from some iterative design work in [#85](https://github.com/domenic/promises-unwrapping/issues/85).

1. If this method was not invoked as a result of explicit user action, return a promise rejected with a new `DOMException` whose name is `"SecurityError"`.
1. If the document's mode of operation is standalone, return a promise rejected with a new `DOMException` whose name is `"NotSupported"`.
1. Let _promise_ be a new promise.
1. Let _info_ be the result of getting a web application's metadata.
1. Using _info_, and in a manner that is user-agent specific, allow the end user to make a choice as to whether they want to add the bookmark.
    1. If the end-user aborts the request to add the bookmark (e.g., they hit escape, or press a "cancel" button), reject _promise_ with a new `DOMException` whose name is `"AbortError"`.
    1. Otherwise, resolve _promise_ with **undefined**.
1. Return _promise_.
