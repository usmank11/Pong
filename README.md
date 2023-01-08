# Pong
Pong game written in SystemVerilog

To simulate, you will need Verilator and SDL. To install on mac, run:
```
brew install verilator sdl2
```

To build, open a terminal in project directory and run:
```
verilator -I../ -cc pong.sv --exe main.cpp -o pong \
    -CFLAGS "$(sdl2-config --cflags)" -LDFLAGS "$(sdl2-config --libs)"

make -C ./obj_dir -f Vpong.mk
```

To run the simulation:
```
./obj_dir/pong
```
<img width="492" alt="Screenshot 2023-01-08 at 6 28 24 PM" src="https://user-images.githubusercontent.com/74438849/211224330-cac569bd-aa83-4ce2-b13f-f28af7ed9eb5.png">
