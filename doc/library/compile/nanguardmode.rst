
.. _nanguardmode:

===================
:mod:`nanguardmode`
===================

.. module:: aesara.compile.nanguardmode
   :platform: Unix, Windows
   :synopsis: defines NanGuardMode
.. moduleauthor:: LISA

Guide
=====


The NanGuardMode aims to prevent the model from outputting NaNs or Infs. It has
a number of self-checks, which can help to find out which apply node is
generating those incorrect outputs. It provides automatic detection of 3 types
of abnormal values: NaNs, Infs, and abnormally big values.

NanGuardMode can be used as follows:

.. testcode::

    import numpy
    import aesara
    import aesara.tensor as at
    from aesara.compile.nanguardmode import NanGuardMode

    x = at.matrix()
    w = aesara.shared(numpy.random.randn(5, 7).astype(aesara.config.floatX))
    y = at.dot(x, w)
    fun = aesara.function(
        [x], y,
        mode=NanGuardMode(nan_is_error=True, inf_is_error=True, big_is_error=True)
    )

While using the aesara function ``fun``, it will monitor the values of each
input and output variable of each node. When abnormal values are
detected, it raises an error to indicate which node yields the NaNs. For
example, if we pass the following values to ``fun``:

.. testcode::

    infa = numpy.tile(
        (numpy.asarray(100.) ** 1000000).astype(aesara.config.floatX), (3, 5))
    fun(infa)

.. testoutput::
   :hide:
   :options: +ELLIPSIS

   Traceback (most recent call last):
     ...
   AssertionError: ...

It will raise an AssertionError indicating that Inf value is detected while
executing the function.

You can also set the three parameters in ``NanGuardMode()`` to indicate which
kind of abnormal values to monitor. ``nan_is_error`` and ``inf_is_error`` has
no default values, so they need to be set explicitly, but ``big_is_error`` is
set to be ``True`` by default.

.. note::

        NanGuardMode significantly slows down computations; only
        enable as needed.

Reference
=========

.. autoclass:: aesara.compile.nanguardmode.NanGuardMode
