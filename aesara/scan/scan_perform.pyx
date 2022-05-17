# cython: language_level=3
"""
 This code implements the operations that scan has to carry on when called
 as a stand alone function.

 IF anything this is the entire code that needs to be transported to C.

 Short description of how this code works:
     Scan divides its inputs ( Op's inputs) into different classes of inputs
     as follows:
         i) sequences : inputs over which scan loops to get data. Nothing is
         written into them ( they are readonly, loop over)

         ii) mit_mot : multiple input taps multiple output taps arguments.
         These are inputs over which scan loops and gets data but into which
         scan also writes data. The shorthand mit_mot describes how scan
         deal with them at each step : at each step take several slices as
         input and produce several slices as outputs

         iii) mit_sot : multiple input taps single output tap arguments.
         As before scan reads from these but also writes. At each step scan
         uses several slices as input but produces only one as output

         iv) sit_sot : single input tap single output tap arguments.
         At each step use only the previous slice as input, produce only one
         slice as output

         v) nit_sot: no input tap single output tap arguments.
         At each step don't use any previous values, only produce new onese

         vi) shared_outs: arguments corresponding to shared variables with
         updates.
         At each step use its value as input, and afterwards replace it with
         a new value.
         vii) other_args: arguments that are passed to every call of the
         inner function as they are ( no slicing is performed)

    All these outputs are one after the other in the inputs list (named in
    this code as outer_inputs) in a given order ( namely the one described above
    with little discrepancies depending if we are talking about the outputs
    of the Scan op or the inputs of the Scan op Node, and if we are talking
    about the inputs of the inner function of scan or of the scan op).

    Because of this, all we need to be able to separate and tell arguments
    apart is how many of which we have as well as how many taps and which
    ones (where applicable). All this information is described (more or less)
    by describing the arguments of this function)
"""
import cython
import numpy

cimport numpy

import copy
import time
import sys

from aesara.scan.utils import InnerFunctionError


def get_version():
    return 0.315

@cython.boundscheck(False)
def perform(
        unsigned int n_shared_outs,
        unsigned int n_mit_mot_outs,
        unsigned int n_seqs,
        unsigned int n_mit_mot,
        unsigned int n_mit_sot,
        unsigned int n_sit_sot,
        unsigned int n_nit_sot,
        bint as_while,
        numpy.ndarray[numpy.int32_t,ndim=1] mintaps,
        tuple tap_array,
        tuple tap_array_len,
        numpy.ndarray[numpy.int32_t,ndim=1] vector_seqs,
        numpy.ndarray[numpy.int32_t,ndim=1] vector_outs,
        tuple mit_mot_out_slices,
        numpy.ndarray[numpy.int32_t,ndim=1] mitmots_preallocated,
        numpy.ndarray[numpy.int32_t,ndim=1] outs_is_tensor,
        list inner_input_storage,
        list inner_output_storage,
        numpy.ndarray[numpy.int32_t,ndim=1] destroy_map,
        list outer_inputs,
        list outer_outputs,
        tuple outer_output_dtypes,
        tuple outer_output_ndims,
        fn,
) -> (float, int):
    """
    Parameters
    ----------
    n_shared_outs: unsigned int
        Number of arguments that correspond to shared variables with
        updates
    n_mit_mot_outs: unsigned int
        Sum over the number of output taps for each mit_mot sequence
    n_seqs: unsigned int
        Number of sequences provided as input
    n_mit_mot : unsigned int
        Number of mit_mot arguments
    n_mit_sot: unsigned int
        Number of mit_sot arguments
    n_sit_sot: unsigned int
        Number of sit sot arguments
    n_nit_sot: unsigned int
        Number of nit_sot arguments
    mintaps: int32 ndarray (can also be a simple python list if that is better !)
        For any of the mit_mot, mit_sot, sit_sot says which is the furtherst
        away input tap from current position. For example, if the taps where [-2,
        -5, -9], the mintap would be -9. For sit_sot this is always -1 since
        is the only allowed tap.
    tap_array
        For each of the mit_mot, mit_sot, sit_sot (the first dimension) says
        which are the corresponding input taps. While this is a matrix, not all
        values in a row are needed and tap_array_len is there to say up to
        which entry we are dealing with valid taps ( afterwards there are
        just 0s to ensure the fix format)
    tap_array_len
        For each of the mit_mot, mit_sot, sit_sot says how many input taps
        each has. For sit_sot this will always be 1.
    vector_seqs: int32 ndarray (can be replaced by a list of bools if better)
        For each sequence the corresponding entry is either a 1, is the
        sequence is a vector or 0 if it has more than 1 dimension
    vector_outs: int32 ndarray( can be replaced by list of bools if better)
        For each output ( mit_mot, mit_sot, sit_sot, nit_sot in this order)
        the entry is 1 if the corresponding argument is a 1 dimensional
        tensor, 0 otherwise.
    mit_mot_out_slices
        Same as tap_array, but for the output taps of mit_mot sequences
    outs_is_tensor : int32 ndarray (Can be replaced by a list)
        Array of boolean indicating, for every output, whether it is a tensor
        or not
    inner_input_storage
        The storage locations for the inner-function's inputs.
    inner_output_storage
        The storage locations for the inner-function's outputs.
    fnct: Function
        The compiled Aesara inner-function object.
    destroy_map
        Array of boolean saying if an output is computed inplace
    outer_inputs: list of ndarrays (and random states)
        The inputs of scan in a given order ( n_steps, sequences, mit_mot,
        mit_sot, sit_sot, nit_sot, shared_outs, other_args)
    outer_outputs: list of 1 element list ( or storage objects?)
        This is where we need to copy our outputs ( we don't return the
        results, though we can change the code such that we return, and
        figure things out on the outside - python)
    outer_output_dtypes
        The dtypes for each outer output.
    outer_output_ndims
        The number of dimensions for each outer output.
    fn
        The inner function thunk.

    """
    # 1. Unzip the number of steps and sequences. If number of steps is
    # negative flip sequences around, and make n_steps positive
    cdef float t_fn = 0
    cdef unsigned int n_steps = outer_inputs[0].item()
    cdef unsigned int n_outs = n_mit_mot + n_mit_sot + n_sit_sot
    cdef unsigned int seqs_arg_offset = n_seqs + 1
    cdef unsigned int shared_arg_offset = ( 1 + n_seqs + n_mit_mot +
                                           n_mit_sot + n_sit_sot)
    cdef unsigned int nit_sot_arg_offset = ( shared_arg_offset +
                                            n_shared_outs)
    cdef unsigned int offset_out
    cdef unsigned int lenpos = n_outs + n_nit_sot
    # TODO: See how this is being converted and whether or not we can remove
    # fixed allocations caused by this.
    cdef int pos[500] # put a maximum of 500 outputs
    cdef unsigned int len_store_steps = n_mit_mot + n_mit_sot + n_sit_sot + n_nit_sot
    # The length of each output
    # TODO: See how this is being converted and whether or not we can remove
    # fixed allocations caused by this.
    cdef int store_steps[500]
    cdef unsigned int l
    cdef unsigned int offset
    cdef int tap
    cdef int _idx
    cdef unsigned int a_offset
    cdef unsigned int o_offset
    cdef unsigned int idx
    cdef unsigned int i
    cdef unsigned int j
    cdef int k
    cdef unsigned int kdx
    cdef unsigned int tdx
    cdef unsigned int pdx
    cdef unsigned int jout
    cdef unsigned int begin
    cdef unsigned int end
    cdef int cond
    cdef unsigned int len_output_storage = (n_mit_mot_outs + n_mit_sot +
                                            n_sit_sot + n_nit_sot +
                                            n_shared_outs)

    if n_steps < 0:
        # History, in the past, this was used for backward
        # scan. Now we reverse the inputs outside of scan.
        raise IndexError(
            "Scan was asked to run for negative number of step %d" %
            n_steps)
    else:
        for idx in range(n_seqs):
            if outer_inputs[<unsigned int>(1+idx)].shape[0] < n_steps:
                raise ValueError((
                    "Sequence %s has shape %s "
                    "but the Scan's required number of steps is %s"
                ) % (
                    idx,
                    outer_inputs[1+idx].shape,
                    n_steps,
                ))

    # 2. Allocate memory for the outputs. Construct the list:

    for idx in range(n_mit_mot + n_mit_sot + n_sit_sot):
        store_steps[<unsigned int>idx] = outer_inputs[<unsigned int>(idx+n_seqs+1)].shape[0]

    for idx in range(n_nit_sot):
        store_steps[<unsigned int>(idx + n_mit_mot + n_mit_sot + n_sit_sot)]=\
                outer_inputs[<unsigned int>(idx + n_mit_mot + n_mit_sot + n_sit_sot
                                    + n_shared_outs + n_seqs+1)]

    # 2.1 Create storage space for outputs
    for idx in range(n_outs):
        if destroy_map[idx] != 0:
            # ^ Case 1. Outputs should be computed inplace of their
            # initial state
            outer_outputs[idx][0] = outer_inputs[ <unsigned int>(1+ n_seqs + idx)]
        elif ( outer_outputs[idx][0] is not None and
              outer_outputs[idx][0].shape[1:] == outer_inputs[<unsigned int>(1+ n_seqs + idx)].shape[1:]
              and outer_outputs[idx][0].shape[0] >= store_steps[idx] ):
            # Put in the values of the initial state
            outer_outputs[idx][0] = outer_outputs[idx][0][:store_steps[idx]]
            if idx > n_mit_mot:
                l = - mintaps[idx]
                outer_outputs[idx][0][:l] = outer_inputs[<unsigned int>(seqs_arg_offset +
                                                       idx)][:l]
            else:
                outer_outputs[idx][0][:] = outer_inputs[<unsigned int>(seqs_arg_offset + idx)]
        else:
            outer_outputs[idx][0] = outer_inputs[<unsigned int>(seqs_arg_offset + idx)].copy()

    if n_steps == 0:
        for idx in range(n_outs, n_outs + n_nit_sot):
            if outs_is_tensor[idx]:
                # TODO FIXME: Why have an `outs_is_tensor` when you can access
                # the node directly?
                # (The answer is that you shouldn't have a `node` object to
                # access, because it's not going to produce a very efficient
                # Cython function!)
                outer_outputs[idx][0] = numpy.empty((0,) * outer_output_ndims[idx], dtype=outer_output_dtypes[idx])
            else:
                outer_outputs[idx][0] = None
        return 0.0, 0

    for idx in range(n_outs + n_nit_sot):
        pos[idx] = -mintaps[idx] % store_steps[idx]

    offset = nit_sot_arg_offset + n_nit_sot
    other_args = outer_inputs[offset:]

    nb_mitmot_in = 0
    for idx in range(n_mit_mot):
        nb_mitmot_in += tap_array_len[idx]

    old_mitmot_input_storage = [None] * nb_mitmot_in
    old_mitmot_input_data = [None] * nb_mitmot_in
    old_output_storage = [None] * len_output_storage
    old_output_data = [None] * len_output_storage
    offset = n_seqs
    for idx in range(n_outs):
        offset += tap_array_len[idx]
    offset += n_shared_outs

    for idx in range(len(other_args)):
        inner_input_storage[<unsigned int>(idx+offset)][0] = other_args[idx]

    i = 0
    cond = 1
    ############## THE MAIN LOOP #########################
    #for i in range(n_steps):
    while (i < n_steps) and cond == 1:
        # sequences over which scan iterates
        # 3. collect input slices
        for idx in range(n_seqs):
            if vector_seqs[idx] == 1:
                inner_input_storage[idx][0] = outer_inputs[\
                            <unsigned int>(1+idx)][i:<unsigned int>(i+1)].reshape(())
            else:
                inner_input_storage[idx][0] = \
                        outer_inputs[<unsigned int>(idx+1)][i]

        offset = n_seqs
        for idx in range(n_outs):
            if vector_outs[idx] == 1:
                for tap in tap_array[idx]:
                    _idx = (pos[idx]+tap)%store_steps[idx]
                    inner_input_storage[offset][0] =\
                            outer_outputs[idx][0][_idx:<unsigned int>(_idx+1)].reshape(())
                    offset += 1
            else:
                for tap in tap_array[idx]:
                    _idx = (pos[idx]+tap)%store_steps[idx]
                    inner_input_storage[offset][0] = outer_outputs[idx][0][_idx]
                    offset += 1


        a_offset = shared_arg_offset
        o_offset = n_outs + n_nit_sot
        if i == 0:
            for j in range(n_shared_outs):
                inner_input_storage[offset][0] = outer_inputs[<unsigned int>(a_offset+j)]
                offset += 1
        else:
            for j in range(n_shared_outs):
                inner_input_storage[offset][0] = outer_outputs[<unsigned int>(o_offset+j)][0]
                offset += 1

        # 4. collecting slices where the output should be stored

        # 4.1. Collect slices for mitmots
        offset = 0
        for idx in range(n_mit_mot_outs):
            if not mitmots_preallocated[<unsigned int>idx]:
                inner_output_storage[<unsigned int>offset][0] = None
            offset += 1

        # 4.2. Collect slices for mitsots, sitsots and nitsots
        if i != 0:
            for idx in range(n_outs + n_nit_sot - n_mit_mot):
                if ( store_steps[<unsigned int>(idx+n_mit_mot)] == 1 or
                    vector_outs[<unsigned int>(idx+n_mit_mot)] == 1):
                    inner_output_storage[<unsigned int>(idx+offset)][0] = None
                else:
                    inner_output_storage[<unsigned int>(idx+offset)][0] =\
                        outer_outputs[<unsigned int>(idx+n_mit_mot)][0][pos[\
                                            <unsigned int>(idx+n_mit_mot)]]
        else:
            for idx in range(n_outs + n_nit_sot - n_mit_mot):
                inner_output_storage[<unsigned int>(idx+offset)][0] = None

        # 4.3. Collect slices for shared outputs
        offset += n_outs+n_nit_sot - n_mit_mot
        for idx in range(n_shared_outs):
            inner_output_storage[<unsigned int>(idx+offset)][0] = None

        # 4.4. If there is a condition add it to the mix
        if as_while:
            pdx = offset + n_shared_outs
            inner_output_storage[<unsigned int>pdx][0] = None

        # 4.5. Keep a reference to the variables (ndarrays,
        # etc) currently in the inner_output_storage to be able to compare them
        # with the actual outputs of the inner function after its
        # execution. Also keep pointers to their data to be able to detect
        # cases where outputs reused the allocated object but alter the
        # memory region they refer to.
        for idx in range(len_output_storage):

            var = inner_output_storage[idx][0]
            old_output_storage[idx] = var

            if var is None:
                old_output_data[idx] = None
            else:
                old_output_data[idx] = var.data

        # 4.6. Keep a reference to the variables (ndarrays,
        # etc) associated with mitmot inputs currently in the inner_input_storage to
        # be able to compare them with the content of the inner_input_storage after
        # the execution of the function. Also keep pointers to their data to
        # be able to detect cases where outputs reused the allocated object
        # but alter the memory region they refer to.
        for idx in xrange(nb_mitmot_in):
            var = inner_input_storage[idx + n_seqs][0]
            old_mitmot_input_storage[idx] = var

            if var is None:
                old_mitmot_input_data[idx] = None
            else:
                old_mitmot_input_data[idx] = var.data

        # 5.1 compute outputs
        t0_fn = time.time()

        try:
            fn()
        except Exception as exc:
            raise InnerFunctionError(exc, sys.exc_info()[-1])

        dt_fn = time.time() - t0_fn
        t_fn += dt_fn
        if as_while:
            pdx = offset + n_shared_outs
            cond = inner_output_storage[pdx][0] == 0

        offset_out = 0

        # 5.3 Copy over the values for mit_mot outputs
        mitmot_inp_offset = 0
        mitmot_out_idx = 0
        for j in xrange(n_mit_mot):
            for k in mit_mot_out_slices[j]:
                if mitmots_preallocated[<unsigned int>mitmot_out_idx]:
                    # This output tap has been preallocated.
                    inp_idx = (mitmot_inp_offset + tap_array[j].index(k))
                    inner_inp_idx = n_seqs + inp_idx

                    # Verify whether the input points to the same data as
                    # it did before the execution of the inner function.
                    old_var = old_mitmot_input_storage[inp_idx]
                    new_var = inner_input_storage[inner_inp_idx][0]
                    if old_var is new_var:
                        old_data = old_mitmot_input_data[inp_idx]
                        same_data = (new_var.data == old_data)
                    else:
                        same_data = False

                    # If the corresponding input storage has been replaced,
                    # recover the value as usual. Otherwise, the input was
                    # modified inplace and nothing needs to be done.
                    if not same_data:
                        outer_outputs[j][0][<unsigned int>(k + pos[j])] = \
                            inner_input_storage[<unsigned int>(inner_inp_idx)][0]

                else:
                    # This output tap has not been preallocated, recover
                    # its value as usual
                    outer_outputs[j][0][<unsigned int>(k + pos[j])] = \
                            inner_output_storage[<unsigned int>offset_out][0]

                offset_out += 1
                mitmot_out_idx += 1

            mitmot_inp_offset += tap_array_len[j]

        # 5.4 Copy over the values for mit_sot/sit_sot outputs
        begin = n_mit_mot
        end   = n_outs
        offset_out -= n_mit_mot

        for j in range(begin, end):

            # Copy the output value to `outer_outputs`, if necessary
            if store_steps[j] == 1 or vector_outs[j] == 1:
                outer_outputs[j][0][pos[j]] = inner_output_storage[<unsigned int>(offset_out+j)][0]
            else:
                # Check whether the initialization of the output storage map
                # for this output has been reused.
                old_var = old_output_storage[offset_out + j]
                old_data = old_output_data[offset_out + j]
                new_var = inner_output_storage[offset_out + j][0]
                if old_var is new_var:
                    if old_data is None:
                        output_reused = False
                    else:
                        output_reused = (new_var.data == old_data)
                else:
                    output_reused = False

                if not output_reused:
                    outer_outputs[j][0][pos[j]] = \
                        inner_output_storage[<unsigned int>(offset_out+j)][0]


        # 5.5 Copy over the values for nit_sot outputs
        begin  = end
        end   += n_nit_sot
        for j in range(begin,end):

            if i == 0:
                jout = j+offset_out
                shape = (store_steps[j],) + inner_output_storage[jout][0].shape
                dtype = inner_output_storage[jout][0].dtype
                if (outer_outputs[j][0] is None or
                        outer_outputs[j][0].shape[0] < store_steps[j] or
                        outer_outputs[j][0].shape[1:] != shape[1:] or
                        outer_outputs[j][0].dtype != dtype ):
                    outer_outputs[j][0] = numpy.empty(shape, dtype=outer_output_dtypes[j])
                elif outer_outputs[j][0].shape[0] != store_steps[j]:
                    outer_outputs[j][0] = outer_outputs[j][0][:store_steps[j]]
                outer_outputs[j][0][pos[j]] = inner_output_storage[jout][0]
            elif store_steps[j] == 1 or vector_outs[j] == 1:
                outer_outputs[j][0][pos[j]] = inner_output_storage[j+offset_out][0]
            else:
                # Check whether the initialization of the output storage map
                # for this output has been reused.
                old_var = old_output_storage[offset_out + j]
                old_data = old_output_data[offset_out + j]
                new_var = inner_output_storage[offset_out + j][0]
                if old_var is new_var:
                    if old_data is None:
                        output_reused = False
                    else:
                        output_reused = (new_var.data == old_data)
                else:
                    output_reused = False

                if not output_reused:
                    try:
                        outer_outputs[j][0][pos[j]] = inner_output_storage[j+offset_out][0]
                    except ValueError as e:
                        if i == 0:
                            raise
                        raise ValueError(
                            "An output of the Scan has changed shape. "
                            "This may be caused by a push-out optimization."
                            " Try adding 'optimizer_excluding=scan_pushout'"
                            " to your Aesara flags.")

        # 5.6 Copy over the values for outputs corresponding to shared
        # variables
        begin  = end
        end   += n_shared_outs
        for j in range(begin,end):
            jout = j +offset_out
            outer_outputs[j][0] = inner_output_storage[jout][0]

        for idx in range(lenpos):
            pos[idx] = (pos[idx]+1)%store_steps[idx]
        i = i + 1

    # 6. Check if you need to re-order output buffers
    begin = n_mit_mot
    end   = n_outs + n_nit_sot
    for idx in range(begin, end):
        if ( store_steps[idx] < i-mintaps[idx] and
            pos[idx] < store_steps[idx] ):

            pdx = pos[idx]
            if pdx >= store_steps[idx]//2 :
                # It seems inefficient to copy the bigger part of the
                # array over, and back, but it is the only way that
                # there is no overlap in the areas of out[idx][0] that
                # are read and written.
                # This way, there will be no information overwritten
                # before it is read (as it used to happen).
                shape = (pdx,)+ outer_outputs[idx][0].shape[1:]
                tmp = numpy.empty(shape, dtype=outer_output_dtypes[idx])
                tmp[:] = outer_outputs[idx][0][:pdx]
                outer_outputs[idx][0][:store_steps[idx]-pdx] = outer_outputs[idx][0][pdx:]
                outer_outputs[idx][0][store_steps[idx]-pdx:] = tmp
            else:
                shape = (store_steps[idx]-pdx,) + outer_outputs[idx][0].shape[1:]
                tmp = numpy.empty(shape, dtype=outer_output_dtypes[idx])
                tmp[:] = outer_outputs[idx][0][pdx:]
                outer_outputs[idx][0][store_steps[idx]-pdx:] = outer_outputs[idx][0][:pdx]
                outer_outputs[idx][0][:store_steps[idx]-pdx] = tmp

        # This would normally happen only when doing truncated
        # backpropagation through time. In such a scenario Scan is
        # expected to return 0 for all entries for which the gradient is
        # not actually computed
        elif store_steps[idx] > i - mintaps[idx]:
            outer_outputs[idx][0][i - mintaps[idx]:] = 0

            # This is a fix for a bug introduced by while. If you say
            # you want to loop up to a condition, you expect the output
            # to have that length ( and not the maximal length possible)
            #
            # Without this the behaviour of a scan op is not consistent
            # if optimization gets applied compared to when optimization
            # do not get applied
            if i < n_steps:

                # Cython can not handle negative indices ( because of a
                # directive at the beginning of the function that says not
                # to do boundschecks). The directive is used to make the
                # code faster, so this workaround is better then removing
                # the directive.
                sh0 = outer_outputs[idx][0].shape[0]
                outer_outputs[idx][0] = outer_outputs[idx][0][:sh0-(n_steps - i)]

    # We never reuse the input or output storage of the
    # inner function so we clear it.
    for s in inner_input_storage:
        s[0] = None
    for s in inner_output_storage:
        s[0] = None

    return t_fn, i
