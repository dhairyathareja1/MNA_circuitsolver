# Circuit Solver

This is a basic DC circuit solver made in MATLAB. It uses Modified Nodal Analysis (MNA) to solve circuits from a `.cir` netlist file.

## Features

- Supports up to 40 non-ground nodes.
- Supports resistors.
- Supports independent DC voltage sources.
- Supports independent DC current sources.
- Supports voltage controlled current sources (VCCS).
- Supports voltage controlled voltage sources (VCVS).
- Supports current controlled current sources (CCCS).
- Supports current controlled voltage sources (CCVS).
- Supports ideal opamps.
- Accepts `0`, `gnd`, or `ground` as the ground node.
- Displays node voltages and extra MNA branch currents.
- Returns the result and MNA matrices in a MATLAB structure.

## Basic Usage

```matlab
result = ec25116031('example.cir');
```

```matlab
result.A
```

## Resource Used

- https://www.mathworks.com/help/matlab/ref/double.mldivide.html
- https://in.mathworks.com/help/matlab/programming-and-data-types.html
