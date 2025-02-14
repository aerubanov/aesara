
.. _basictutexamples:

=============
More Examples
=============

At this point it would be wise to begin familiarizing yourself more
systematically with Aesara's fundamental objects and operations by
browsing this section of the library: :ref:`libdoc_basic_tensor`.

As the tutorial unfolds, you should also gradually acquaint yourself
with the other relevant areas of the library and with the relevant
subjects of the documentation entrance page.


Logistic Function
=================

Here's another straightforward example, though a bit more elaborate
than adding two numbers together. Let's say that you want to compute
the logistic curve, which is given by:

.. math::

   s(x) = \frac{1}{1 + e^{-x}}

.. figure:: logistic.png

    A plot of the logistic function, with x on the x-axis and s(x) on the
    y-axis.

You want to compute the function :ref:`element-wise
<libdoc_tensor_elemwise>` on matrices of doubles, which means that
you want to apply this function to each individual element of the
matrix.

Well, what you do is this:

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_1

>>> import aesara
>>> import aesara.tensor as at
>>> x = at.dmatrix('x')
>>> s = 1 / (1 + at.exp(-x))
>>> logistic = aesara.function([x], s)
>>> logistic([[0, 1], [-1, -2]])
array([[ 0.5       ,  0.73105858],
       [ 0.26894142,  0.11920292]])

The reason logistic is performed elementwise is because all of its
operations---division, addition, exponentiation, and division---are
themselves elementwise operations.

It is also the case that:

.. math::

    s(x) = \frac{1}{1 + e^{-x}} = \frac{1 + \tanh(x/2)}{2}

We can verify that this alternate form produces the same values:

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_2

>>> s2 = (1 + at.tanh(x / 2)) / 2
>>> logistic2 = aesara.function([x], s2)
>>> logistic2([[0, 1], [-1, -2]])
array([[ 0.5       ,  0.73105858],
       [ 0.26894142,  0.11920292]])


Computing More than one Thing at the Same Time
==============================================

Aesara supports functions with multiple outputs. For example, we can
compute the :ref:`element-wise <libdoc_tensor_elemwise>` difference, absolute difference, and
squared difference between two matrices *a* and *b* at the same time:

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_3

>>> a, b = at.dmatrices('a', 'b')
>>> diff = a - b
>>> abs_diff = abs(diff)
>>> diff_squared = diff**2
>>> f = aesara.function([a, b], [diff, abs_diff, diff_squared])

.. note::
   `dmatrices` produces as many outputs as names that you provide.  It is a
   shortcut for allocating symbolic variables that we will often use in the
   tutorials.

When we use the function f, it returns the three variables (the printing
was reformatted for readability):

>>> f([[1, 1], [1, 1]], [[0, 1], [2, 3]])
[array([[ 1.,  0.],
       [-1., -2.]]), array([[ 1.,  0.],
       [ 1.,  2.]]), array([[ 1.,  0.],
       [ 1.,  4.]])]


Setting a Default Value for an Argument
=======================================

Let's say you want to define a function that adds two numbers, except
that if you only provide one number, the other input is assumed to be
one. You can do it like this:

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_6

>>> from aesara.compile.io import In
>>> from aesara import function
>>> x, y = at.dscalars('x', 'y')
>>> z = x + y
>>> f = function([x, In(y, value=1)], z)
>>> f(33)
array(34.0)
>>> f(33, 2)
array(35.0)

This makes use of the :ref:`In <function_inputs>` class which allows
you to specify properties of your function's parameters with greater detail. Here we
give a default value of 1 for *y* by creating a ``In`` instance with
its ``value`` field set to 1.

Inputs with default values must follow inputs without default
values (like Python's functions).  There can be multiple inputs with default values. These parameters can
be set positionally or by name, as in standard Python:


.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_7

>>> x, y, w = at.dscalars('x', 'y', 'w')
>>> z = (x + y) * w
>>> f = function([x, In(y, value=1), In(w, value=2, name='w_by_name')], z)
>>> f(33)
array(68.0)
>>> f(33, 2)
array(70.0)
>>> f(33, 0, 1)
array(33.0)
>>> f(33, w_by_name=1)
array(34.0)
>>> f(33, w_by_name=1, y=0)
array(33.0)

.. note::
   ``In`` does not know the name of the local variables *y* and *w*
   that are passed as arguments.  The symbolic variable objects have name
   attributes (set by ``dscalars`` in the example above) and *these* are the
   names of the keyword parameters in the functions that we build.  This is
   the mechanism at work in ``In(y, value=1)``.  In the case of ``In(w,
   value=2, name='w_by_name')``. We override the symbolic variable's name
   attribute with a name to be used for this function.


You may like to see :ref:`Function<usingfunction>` in the library for more detail.


.. _functionstateexample:

Using Shared Variables
======================

It is also possible to make a function with an internal state. For
example, let's say we want to make an accumulator: at the beginning,
the state is initialized to zero. Then, on each function call, the state
is incremented by the function's argument.

First let's define the *accumulator* function. It adds its argument to the
internal state, and returns the old state value.

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_8

>>> from aesara import shared
>>> state = shared(0)
>>> inc = at.iscalar('inc')
>>> accumulator = function([inc], state, updates=[(state, state+inc)])

This code introduces a few new concepts.  The ``shared`` function constructs
so-called :ref:`shared variables<libdoc_compile_shared>`.
These are hybrid symbolic and non-symbolic variables whose value may be shared
between multiple functions.  Shared variables can be used in symbolic expressions just like
the objects returned by ``dmatrices(...)`` but they also have an internal
value that defines the value taken by this symbolic variable in *all* the
functions that use it.  It is called a *shared* variable because its value is
shared between many functions.  The value can be accessed and modified by the
``.get_value()`` and ``.set_value()`` methods. We will come back to this soon.

The other new thing in this code is the ``updates`` parameter of ``function``.
``updates`` must be supplied with a list of pairs of the form (shared-variable, new expression).
It can also be a dictionary whose keys are shared-variables and values are
the new expressions.  Either way, it means "whenever this function runs, it
will replace the ``.value`` of each shared variable with the result of the
corresponding expression".  Above, our accumulator replaces the ``state``'s value with the sum
of the state and the increment amount.

Let's try it out!

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_8

>>> print(state.get_value())
0
>>> accumulator(1)
array(0)
>>> print(state.get_value())
1
>>> accumulator(300)
array(1)
>>> print(state.get_value())
301

It is possible to reset the state. Just use the ``.set_value()`` method:

>>> state.set_value(-1)
>>> accumulator(3)
array(-1)
>>> print(state.get_value())
2

As we mentioned above, you can define more than one function to use the same
shared variable.  These functions can all update the value.

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_8

>>> decrementor = function([inc], state, updates=[(state, state-inc)])
>>> decrementor(2)
array(2)
>>> print(state.get_value())
0

You might be wondering why the updates mechanism exists.  You can always
achieve a similar result by returning the new expressions, and working with
them in NumPy as usual.  The updates mechanism can be a syntactic convenience,
but it is mainly there for efficiency.  Updates to shared variables can
sometimes be done more quickly using in-place algorithms (e.g. low-rank matrix
updates).

It may happen that you expressed some formula using a shared variable, but
you do *not* want to use its value. In this case, you can use the
``givens`` parameter of ``function`` which replaces a particular node in a graph
for the purpose of one particular function.

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_8

>>> fn_of_state = state * 2 + inc
>>> # The type of foo must match the shared variable we are replacing
>>> # with the ``givens``
>>> foo = at.scalar(dtype=state.dtype)
>>> skip_shared = function([inc, foo], fn_of_state, givens=[(state, foo)])
>>> skip_shared(1, 3)  # we're using 3 for the state, not state.value
array(7)
>>> print(state.get_value())  # old state still there, but we didn't use it
0

The ``givens`` parameter can be used to replace any symbolic variable, not just a
shared variable. You can replace constants, and expressions, in general.  Be
careful though, not to allow the expressions introduced by a ``givens``
substitution to be co-dependent, the order of substitution is not defined, so
the substitutions have to work in any order.

In practice, a good way of thinking about the ``givens`` is as a mechanism
that allows you to replace any part of your formula with a different
expression that evaluates to a tensor of same shape and dtype.

.. note::

    Aesara shared variable broadcast pattern default to False for each
    dimensions. Shared variable size can change over time, so we can't
    use the shape to find the broadcastable pattern. If you want a
    different pattern, just pass it as a parameter
    ``aesara.shared(..., shape=(True, False))``

Copying functions
=================
Aesara functions can be copied, which can be useful for creating similar
functions but with different shared variables or updates. This is done using
the :func:`copy()<aesara.compile.function.types.Function.copy>` method of ``function`` objects. The optimized graph of the original function is copied,
so compilation only needs to be performed once.

Let's start from the accumulator defined above:

>>> import aesara
>>> import aesara.tensor as at
>>> state = aesara.shared(0)
>>> inc = at.iscalar('inc')
>>> accumulator = aesara.function([inc], state, updates=[(state, state+inc)])

We can use it to increment the state as usual:

>>> accumulator(10)
array(0)
>>> print(state.get_value())
10

We can use ``copy()`` to create a similar accumulator but with its own internal state
using the ``swap`` parameter, which is a dictionary of shared variables to exchange:

>>> new_state = aesara.shared(0)
>>> new_accumulator = accumulator.copy(swap={state:new_state})
>>> new_accumulator(100)
[array(0)]
>>> print(new_state.get_value())
100

The state of the first function is left untouched:

>>> print(state.get_value())
10

We now create a copy with updates removed using the ``delete_updates``
parameter, which is set to ``False`` by default:

>>> null_accumulator = accumulator.copy(delete_updates=True)

As expected, the shared state is no longer updated:

>>> null_accumulator(9000)
[array(10)]
>>> print(state.get_value())
10

.. _using_random_numbers:

Using Random Numbers
====================

Because in Aesara you first express everything symbolically and
afterwards compile this expression to get functions,
using pseudo-random numbers is not as straightforward as it is in
NumPy, though also not too complicated.

The way to think about putting randomness into Aesara's computations is
to put random variables in your graph. Aesara will allocate a NumPy
`RandomStream` object (a random number generator) for each such
variable, and draw from it as necessary. We will call this sort of
sequence of random numbers a *random stream*. *Random streams* are at
their core shared variables, so the observations on shared variables
hold here as well. Aesara's random objects are defined and implemented in
:ref:`RandomStream<libdoc_tensor_random_utils>` and, at a lower level,
in :ref:`RandomVariable<libdoc_tensor_random_basic>`.

Brief Example
-------------

Here's a brief example.  The setup code is:

.. If you modify this code, also change :
.. tests/test_tutorial.py:T_examples.test_examples_9

.. testcode::

    from aesara.tensor.random.utils import RandomStream
    from aesara import function
    srng = RandomStream(seed=234)
    rv_u = srng.uniform(0, 1, size=(2,2))
    rv_n = srng.normal(0, 1, size=(2,2))
    f = function([], rv_u)
    g = function([], rv_n, no_default_updates=True)    #Not updating rv_n.rng
    nearly_zeros = function([], rv_u + rv_u - 2 * rv_u)

Here, ``rv_u`` represents a random stream of 2x2 matrices of draws from a uniform
distribution.  Likewise,  ``rv_n`` represents a random stream of 2x2 matrices of
draws from a normal distribution.  The distributions that are implemented are
defined as :class:`RandomVariable`\s
in :ref:`basic<libdoc_tensor_random_basic>`. They only work on CPU.


Now let's use these objects.  If we call ``f()``, we get random uniform numbers.
The internal state of the random number generator is automatically updated,
so we get different random numbers every time.

>>> f_val0 = f()
>>> f_val1 = f()  #different numbers from f_val0

When we add the extra argument ``no_default_updates=True`` to
``function`` (as in *g*), then the random number generator state is
not affected by calling the returned function.  So, for example, calling
*g* multiple times will return the same numbers.

>>> g_val0 = g()  # different numbers from f_val0 and f_val1
>>> g_val1 = g()  # same numbers as g_val0!

An important remark is that a random variable is drawn at most once during any
single function execution.  So the *nearly_zeros* function is guaranteed to
return approximately 0 (except for rounding error) even though the *rv_u*
random variable appears three times in the output expression.

>>> nearly_zeros = function([], rv_u + rv_u - 2 * rv_u)

Seeding Streams
---------------

Random variables can be seeded individually or collectively.

You can seed just one random variable by seeding or assigning to the
``.rng`` attribute, using ``.rng.set_value()``.

>>> rng_val = rv_u.rng.get_value(borrow=True)   # Get the rng for rv_u
>>> rng_val.seed(89234)                         # seeds the generator
>>> rv_u.rng.set_value(rng_val, borrow=True)    # Assign back seeded rng

You can also seed *all* of the random variables allocated by a :class:`RandomStream`
object by that object's ``seed`` method.  This seed will be used to seed a
temporary random number generator, that will in turn generate seeds for each
of the random variables.

>>> srng.seed(902340)  # seeds rv_u and rv_n with different seeds each

Sharing Streams Between Functions
---------------------------------

As usual for shared variables, the random number generators used for random
variables are common between functions.  So our *nearly_zeros* function will
update the state of the generators used in function *f* above.

For example:

>>> state_after_v0 = rv_u.rng.get_value().get_state()
>>> nearly_zeros()       # this affects rv_u's generator
array([[ 0.,  0.],
       [ 0.,  0.]])
>>> v1 = f()
>>> rng = rv_u.rng.get_value(borrow=True)
>>> rng.set_state(state_after_v0)
>>> rv_u.rng.set_value(rng, borrow=True)
>>> v2 = f()             # v2 != v1
>>> v3 = f()             # v3 == v1

Copying Random State Between Aesara Graphs
------------------------------------------

In some use cases, a user might want to transfer the "state" of all random
number generators associated with a given aesara graph (e.g. g1, with compiled
function f1 below) to a second graph (e.g. g2, with function f2). This might
arise for example if you are trying to initialize the state of a model, from
the parameters of a pickled version of a previous model. For
:class:`aesara.tensor.random.utils.RandomStream` and
:class:`aesara.sandbox.rng_mrg.MRG_RandomStream`
this can be achieved by copying elements of the `state_updates` parameter.

Each time a random variable is drawn from a `RandomStream` object, a tuple is
added to the `state_updates` list. The first element is a shared variable,
which represents the state of the random number generator associated with this
*particular* variable, while the second represents the aesara graph
corresponding to the random number generation process (i.e. RandomFunction{uniform}.0).

An example of how "random states" can be transferred from one aesara function
to another is shown below.

>>> import aesara
>>> import numpy
>>> import aesara.tensor as at
>>> from aesara.sandbox.rng_mrg import MRG_RandomStream
>>> from aesara.tensor.random.utils import RandomStream

>>> class Graph():
...     def __init__(self, seed=123):
...         self.rng = RandomStream(seed)
...         self.y = self.rng.uniform(size=(1,))

>>> g1 = Graph(seed=123)
>>> f1 = aesara.function([], g1.y)

>>> g2 = Graph(seed=987)
>>> f2 = aesara.function([], g2.y)

>>> # By default, the two functions are out of sync.
>>> f1()
array([ 0.72803009])
>>> f2()
array([ 0.55056769])

>>> def copy_random_state(g1, g2):
...     if isinstance(g1.rng, MRG_RandomStream):
...         g2.rng.rstate = g1.rng.rstate
...     for (su1, su2) in zip(g1.rng.state_updates, g2.rng.state_updates):
...         su2[0].set_value(su1[0].get_value())

>>> # We now copy the state of the aesara random number generators.
>>> copy_random_state(g1, g2)
>>> f1()
array([ 0.59044123])
>>> f2()
array([ 0.59044123])


Other Random Distributions
--------------------------

There are :ref:`other distributions implemented <libdoc_tensor_random_basic>`.


.. _logistic_regression:


A Real Example: Logistic Regression
===================================

The preceding elements are featured in this more realistic example.
It will be used repeatedly.

.. testcode::

    import numpy
    import aesara
    import aesara.tensor as at
    rng = numpy.random

    N = 400                                   # training sample size
    feats = 784                               # number of input variables

    # generate a dataset: D = (input_values, target_class)
    D = (rng.randn(N, feats), rng.randint(size=N, low=0, high=2))
    training_steps = 10000

    # Declare Aesara symbolic variables
    x = at.dmatrix("x")
    y = at.dvector("y")

    # initialize the weight vector w randomly
    #
    # this and the following bias variable b
    # are shared so they keep their values
    # between training iterations (updates)
    w = aesara.shared(rng.randn(feats), name="w")

    # initialize the bias term
    b = aesara.shared(0., name="b")

    print("Initial model:")
    print(w.get_value())
    print(b.get_value())

    # Construct Aesara expression graph
    p_1 = 1 / (1 + at.exp(-at.dot(x, w) - b))        # Probability that target = 1
    prediction = p_1 > 0.5                          # The prediction thresholded
    xent = -y * at.log(p_1) - (1-y) * at.log(1-p_1) # Cross-entropy loss function
    cost = xent.mean() + 0.01 * (w ** 2).sum()      # The cost to minimize
    gw, gb = at.grad(cost, [w, b])                  # Compute the gradient of the cost
                                                    # w.r.t weight vector w and
                                                    # bias term b (we shall
                                                    # return to this in a
                                                    # following section of this
                                                    # tutorial)

    # Compile
    train = aesara.function(
              inputs=[x,y],
              outputs=[prediction, xent],
              updates=((w, w - 0.1 * gw), (b, b - 0.1 * gb)))
    predict = aesara.function(inputs=[x], outputs=prediction)

    # Train
    for i in range(training_steps):
        pred, err = train(D[0], D[1])

    print("Final model:")
    print(w.get_value())
    print(b.get_value())
    print("target values for D:")
    print(D[1])
    print("prediction on D:")
    print(predict(D[0]))

.. testoutput::
   :hide:
   :options: +ELLIPSIS

   Initial model:
   ...
   0.0
   Final model:
   ...
   target values for D:
   ...
   prediction on D:
   ...
