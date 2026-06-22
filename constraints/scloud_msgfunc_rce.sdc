# Scloud+ MsgFunc RCE standalone timing constraints
#
# Target: 200 MHz RCE clock (5.000 ns period), as recorded in the active
# technical design. If the integrated SPUV3 RCE uses another frequency,
# replace this period with the clock actually delivered to the subsystem.
#
# This file is for standalone synthesis with top=scloud_msgfunc_rce_accel.
# For integrated spu_subsystem implementation, constrain the real top-level
# primary/generated clock instead and let that clock propagate into this
# accelerator. Do not create a duplicate clock on the internal instance pin.

create_clock -name rce_clk \
    -period 5.000 \
    -waveform {0.000 2.500} \
    [get_ports clk]

# The RTL reset is asynchronously asserted. Exclude reset assertion from data
# timing analysis; reset release must be synchronized by the containing RCE
# subsystem and checked there for recovery/removal behavior.
set_false_path -from [get_ports rst_n]

# Deliberately no set_input_delay/set_output_delay constraints are applied to
# the DPRAM and control/status ports here. They are internal synchronous
# subsystem interfaces, not package pins. Their real timing is established by
# integrated synthesis against the DPRAM, SFR, and arbitration registers.
