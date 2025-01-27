"""
Define `SymbolicInput`, `SymbolicOutput`, `In`, `Out`.

"""


import logging

from aesara.link.basic import Container


_logger = logging.getLogger("aesara.compile.io")

__docformat__ = "restructuredtext en"


class SymbolicInput:
    """
    Represents a symbolic input for use with function or FunctionMaker.

    Parameters
    ----------
    variable : a Variable instance
        This will be assigned a value before running the function, not computed
        from its owner.
    name : Any type
        If autoname=True, defaults to variable.name.
        If name is a valid Python identifier, this input can be set by kwarg,
        and its value can be accessed by self.<name>.
    update : Variable instance
        Defaults to None. Value (see previous) will be replaced with this
        expression variable after each function call. If update is None, the
        update will be the default value of the input.
    mutable : bool
        Defaults to False if update is None, True if update is not None.
        True: permit the compiled function to modify the python object being
        passed as the input.
        False: do not permit the compiled function to modify the python object
        being passed as the input.
    strict : bool
        Defaults to False.
        True: means that the value you pass for this input must have exactly the
        right type.
        False: the value you pass for this input may be cast automatically to
        the proper type.
    allow_downcast : bool or None
        Defaults to None. Only applies when `strict` is False.
        True: the value you pass for this input can be silently downcasted to
        fit the right type, which may lose precision.
        False: the value will only be cast to a more general, or precise, type.
        None: Almost like False, but allows downcast of Python floats to floatX.
    autoname : bool
        Defaults to True. See the name option.
    implicit : bool
        Defaults to False. See help(In). Note that 'None' is not allowed here,
        since we are in the symbolic case.

    """

    def __init__(
        self,
        variable,
        name=None,
        update=None,
        mutable=None,
        strict=False,
        allow_downcast=None,
        autoname=True,
        implicit=False,
    ):
        assert implicit is not None  # Safety check.
        self.variable = variable
        if autoname and name is None:
            self.name = variable.name
        else:
            self.name = name

        if self.name is not None and not isinstance(self.name, str):
            raise TypeError(f"name must be a string! (got: {self.name})")
        self.update = update
        if update is not None:
            if not variable.type.in_same_class(update.type):
                raise TypeError(
                    f"Variable '{variable}' has type {variable.type} but an update of "
                    f"type {update.type}. The type of the update should be "
                    "compatible with the type of the variable."
                )

        if mutable is not None:
            self.mutable = mutable
        else:
            self.mutable = update is not None

        self.strict = strict
        self.allow_downcast = allow_downcast
        self.implicit = implicit

    def __str__(self):
        if self.update:
            return f"In({self.variable} -> {self.update})"
        else:
            return f"In({self.variable})"

    def __repr__(self):
        return str(self)


class In(SymbolicInput):
    """
    Represents a symbolic input for use with function or FunctionMaker.

    Parameters
    ----------
    variable : a Variable instance
        This will be assigned a value before running the function, not computed
        from its owner.
    name : Any type
        If autoname=True, defaults to variable.name.
        If name is a valid Python identifier, this input can be set by kwarg,
        and its value can be accessed by self.<name>.
    value : Any type
        The initial/default value for this input. If update is None,
        this input acts just like an argument with a default value in
        Python. If update is not None, changes to this value will
        "stick around", whether due to an update or a user's explicit
        action.
    update : Variable instance
        Defaults to None. Value (see previous) will be replaced with this
        expression variable after each function call. If update is None, the
        update will be the default value of the input.
    mutable : bool
        Defaults to False if update is None, True if update is not None.
        True: permit the compiled function to modify the python object
        being passed as the input.
        False: do not permit the compiled function to modify the
        python object being passed as the input.
    borrow : bool
        Default : take the same value as mutable.
        True: permit the output of the compiled function to be aliased
        to the input.
        False: do not permit any output to be aliased to the input.
    strict : bool
        Defaults to False.
        True: means that the value you pass for this input must have exactly
        the right type.
        False: the value you pass for this input may be cast automatically to
        the proper type.
    allow_downcast : bool or None
        Defaults to None. Only applies when `strict` is False.
        True: the value you pass for this input can be silently downcasted to
        fit the right type, which may lose precision.
        False: the value will only be cast to a more general, or precise, type.
        None: Almost like False, but allows downcast of Python floats to floatX.
    autoname : bool
        Defaults to True. See the name option.
    implicit : bool or None
        Defaults to None.
        True: This input is implicit in the sense that the user is not allowed
        to provide a value for it. Requires 'value' to be set.
        False: The user can provide a value for this input. Be careful when
        'value' is a container, because providing an input value will
        overwrite the content of this container.
        None: Automatically choose between True or False depending on the
        situation. It will be set to False in all cases except if 'value' is a
        container (so that there is less risk of accidentally overwriting its
        content without being aware of it).

    """

    # Note: the documentation above is duplicated in doc/topics/function.txt,
    # try to keep it synchronized.
    def __init__(
        self,
        variable,
        name=None,
        value=None,
        update=None,
        mutable=None,
        strict=False,
        allow_downcast=None,
        autoname=True,
        implicit=None,
        borrow=None,
        shared=False,
    ):
        # if shared, an input's value comes from its persistent
        # storage, not from a default stored in the function or from
        # the caller
        self.shared = shared

        if borrow is None:
            self.borrow = mutable
        else:
            self.borrow = borrow

        # mutable implies the output can be both aliased to the input and that
        # the input can be destroyed. borrow simply implies the output can be
        # aliased to the input. Thus mutable=True should require borrow=True.
        if mutable and not self.borrow:
            raise AssertionError(
                f"Symbolic input for variable {variable} (name={name}) has "
                "flags mutable=True, borrow=False. This combination is "
                "incompatible since mutable=True implies that the "
                "input variable may be both aliased (borrow=True) and "
                "overwritten.",
            )

        if implicit is None:
            from aesara.compile.sharedvalue import SharedVariable

            implicit = isinstance(value, Container) or isinstance(value, SharedVariable)
        super().__init__(
            variable=variable,
            name=name,
            update=update,
            mutable=mutable,
            strict=strict,
            allow_downcast=allow_downcast,
            autoname=autoname,
            implicit=implicit,
        )
        self.value = value
        if self.implicit and value is None:
            raise TypeError("An implicit input must be given a default value")


class SymbolicOutput:
    """
    Represents a symbolic output for use with function or FunctionMaker.

    Parameters
    ----------
    borrow : bool
        Set this to True to indicate that a reference to function's internal
        storage may be returned. A value returned for this output might be
        clobbered by running the function again, but the function might be
        faster.

    """

    def __init__(self, variable, borrow=False):
        self.variable = variable
        self.borrow = borrow

    def __str__(self):
        return f"Out({self.variable},{self.borrow})"

    def __repr__(self):
        return f"Out({self.variable},{self.borrow})"


Out = SymbolicOutput
