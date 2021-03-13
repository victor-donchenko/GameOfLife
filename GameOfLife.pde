class Coords2d {
  public int row;
  public int col;
  
  public Coords2d(int i_row, int i_col) {
    row = i_row;
    col = i_col;
  }
  
  public Coords2d(Coords2d other) {
    row = other.row;
    col = other.col;
  }
  
  public int hashCode() {
    return row ^ (col << 1);
  }
  
  public boolean equals(Object other) {
    Coords2d coords_other = (Coords2d)other;
    if (coords_other == null) {
      return false;
    }
    else {
      return row == coords_other.row && col == coords_other.col;
    }
  }
};

class Mutex {
  private boolean value;
  
  public Mutex() {
    value = false;
  }
  
  public void acquire() {
    while (value);
    value = true;
  }
  
  public void release() {
    value = false;
  }
}

class CellBuffer {
  public HashMap<Coords2d, Boolean> on_cells;
  
  public CellBuffer() {
    on_cells = new HashMap<Coords2d, Boolean>();
  }
  
  public boolean get_cell(Coords2d coords) {
    return on_cells.containsKey(coords);
  }
  
  public void set_cell(Coords2d coords, boolean value) {
    if (value) {
      on_cells.put(coords, true);
    }
    else {
      if (on_cells.containsKey(coords)) {
        on_cells.remove(coords);
      }
    }
  }
  
  public void toggle_cell(Coords2d coords) {
    set_cell(coords, !get_cell(coords));
  }
}

class GameBoard {
  private CellBuffer cells;
  private Mutex cells_mutex;
  private CellBuffer buffer;
  private boolean updated;
  private boolean changed;
  private int board_width;
  private int board_height;
  private ArrayList<Float> update_millis_queue;
  private int update_millis_queue_front;
  
  public GameBoard(int i_board_width, int i_board_height) {
    board_width = i_board_width;
    board_height = i_board_height;
    cells = new CellBuffer();
    cells_mutex = new Mutex();
    buffer = new CellBuffer();
    updated = true;
    changed = false;
    update_millis_queue = new ArrayList<Float>();
    update_millis_queue_front = 0;
  }
  
  public boolean get_cell(Coords2d coords) {
    return cells.get_cell(coords);
  }
  
  public void toggle_cell(Coords2d coords) {
    cells_mutex.acquire();
    cells.toggle_cell(coords);
    changed = true;
    if (updated) {
      start_update();
    }
    cells_mutex.release();
  }
  
  public Mutex get_mutex() {
    return cells_mutex;
  }
  
  private Coords2d wrap_around(Coords2d coords) {
    Coords2d out = new Coords2d(coords);
    out.row %= board_height;
    out.col %= board_width;
    if (out.row < 0) {
      out.row += board_height;
    }
    if (out.col < 0) {
      out.col += board_width;
    }
    return out;
  }
  
  public void update() {
    updated = false;
    changed = false;
    
    float start_time = millis();
    
    HashMap<Coords2d, Boolean> active_cells = new HashMap<Coords2d, Boolean>();
    
    for (HashMap.Entry<Coords2d, Boolean> entry : cells.on_cells.entrySet()) {
      for (int nr = -1; nr <= 1; ++nr) {
        for (int nc = -1; nc <= 1; ++nc) {
          if (nr == 0 && nc == 0) {
            continue;
          }
          Coords2d coords = entry.getKey();
          Coords2d active_cell_coords = wrap_around(new Coords2d(
            coords.row + nr,
            coords.col + nc
          ));
          active_cells.put(active_cell_coords, cells.get_cell(active_cell_coords));
        }
      }
    }
    
    buffer.on_cells.clear();
    
    for (HashMap.Entry<Coords2d, Boolean> entry : active_cells.entrySet()) {
      Coords2d coords = entry.getKey();
      boolean current_cell = entry.getValue();
      
      int num_neighbors_on = 0;
      for (int nr = -1; nr <= 1; ++nr) {
        for (int nc = -1; nc <= 1; ++nc) {
          if (nr == 0 && nc == 0) {
            continue;
          }
          if (cells.get_cell(wrap_around(new Coords2d(coords.row + nr, coords.col + nc)))) {
            ++num_neighbors_on;
          }
        }
      }
      
      if (!current_cell) {
        if (num_neighbors_on == 3) {
          buffer.set_cell(coords, true);
        }
        else {
          buffer.set_cell(coords, false);
        }
      }
      else {
        if (num_neighbors_on >= 2 && num_neighbors_on <= 3) {
          buffer.set_cell(coords, true);
        }
        else {
          buffer.set_cell(coords, false);
        }
      }
    }
    
    if (changed) {
      start_update();
    }
    else {
      updated = true;
      
      float finish_time = millis();
      
      if (update_millis_queue.size() < 5) {
        update_millis_queue.add(finish_time - start_time);
      }
      else {
        update_millis_queue.set(update_millis_queue_front, finish_time - start_time);
      }
      update_millis_queue_front = (update_millis_queue_front + 1) % 5;
    }
  }
  
  public float get_average_millis_per_update() {
    float sum = 0;
    for (int i = 0; i < update_millis_queue.size(); ++i) {
      sum += update_millis_queue.get(i);
    }
    if (update_millis_queue.size() == 0) {
      return 0;
    }
    else {
      return sum / update_millis_queue.size();
    }
  }
  
  public boolean deploy_update() {
    if (updated && !changed) {
      cells_mutex.acquire();
      CellBuffer temp = cells;
      cells = buffer;
      buffer = temp;
      cells_mutex.release();
      updated = false;
      return true;
    }
    return false;
  }
  
  public void start_update() {
    subject_board = this;
    start_thread(global_update);
  }
}

GameBoard subject_board;

void global_update() {
  subject_board.update();
}

int board_width = 500;
int board_height = 500;

GameBoard board;
float center_cell_offset_row;
float center_cell_offset_col;
float cell_width;
float cell_height;
float last_update_time;
float millis_per_update = 100;
boolean paused;
float zoom_scale = 1.1;

PFont font;

void setup() {
  size(500, 500);
  board = new GameBoard(board_width, board_height);
  center_cell_offset_row = board_height / 2;
  center_cell_offset_col = board_width / 2;
  cell_width = 10;
  cell_height = 10;
  last_update_time = millis();
  paused = true;
  font = createFont("Helvetica", 10);
}

float convert_row_to_y(int row) {
  return cell_height * (row - center_cell_offset_row) + height / 2;
}

float convert_col_to_x(int col) {
  return cell_width * (col - center_cell_offset_col) + width / 2;
}

void draw() {
  background(color(0xff, 0xff, 0xff));
  
  int min_row = (int)(center_cell_offset_row - (height / 2) / cell_height);
  int max_row = (int)(center_cell_offset_row + (height / 2) / cell_height + 1);
  int min_col = (int)(center_cell_offset_col - (width / 2) / cell_width);
  int max_col = (int)(center_cell_offset_col + (width / 2) / cell_width + 1);
  
  if (min_row < 0) {
    min_row = 0;
  }
  if (max_row >= board_height) {
    min_row = board_height - 1;
  }
  if (min_col < 0) {
    min_col = 0;
  }
  if (min_col >= board_width) {
    min_col = board_width - 1;
  }
  
  stroke(color(0xc0, 0xc0, 0xc0));
  
  float min_col_x = convert_col_to_x(min_col);
  float max_col_x = convert_col_to_x(max_col);
  for (int row = min_row; row <= max_row; ++row) {
    float row_y = convert_row_to_y(row);
    line(
      min_col_x,
      row_y,
      max_col_x + cell_width,
      row_y
    );
  }
  
  float min_row_y = convert_row_to_y(min_row);
  float max_row_y = convert_row_to_y(max_row);
  for (int col = min_col; col <= max_col; ++col) {
    float col_x = convert_col_to_x(col);
    line(
      col_x,
      min_row_y,
      col_x,
      max_row_y + cell_height
    );
  }
  
  fill(color(0x00, 0x00, 0x00));
  
  Mutex cells_mutex = board.get_mutex();
  cells_mutex.acquire();
  for (int row = min_row; row <= max_row; ++row) {
    for (int col = min_col; col <= max_col; ++col) {
      if (0 <= row && row < board_height && 0 <= col && col < board_width) {
        boolean cell = board.get_cell(new Coords2d(row, col));
        float ul_corner_x = convert_col_to_x(col);
        float ul_corner_y = convert_row_to_y(row);
        if (cell) {
          rect(
            ul_corner_x,
            ul_corner_y,
            cell_width,
            cell_height
          );
        }
      }
    }
  }
  cells_mutex.release();

  textFont(font);

  String status_text;
  if (paused) {
    status_text = "Paused";
  }
  else {
    status_text = "Running";
  }
  textSize(10);
  textAlign(LEFT, TOP);
  text(status_text, 10, 10);
  
  String status_text2 = "Milliseconds per update cap: " + millis_per_update;
  status_text2 = status_text2 + "; average milliseconds per update: " + board.get_average_millis_per_update();
  textSize(10);
  textAlign(LEFT, BOTTOM);
  text(status_text2, 10, height - 10);

  if (!paused) {
    float time = millis();
    if (time - last_update_time >= millis_per_update) {
      boolean finished = board.deploy_update();
      if (finished) {
        board.start_update();
      }
      last_update_time = time;
    }
  }
  else {
    last_update_time = millis();
  }
}

void mouseClicked() {
  int row = (int)((mouseY - height / 2) / cell_height + center_cell_offset_row);
  int col = (int)((mouseX - width / 2) / cell_width + center_cell_offset_col);
  if (0 <= row && row < board_height && 0 <= col && col < board_width) {
    board.toggle_cell(new Coords2d(row, col));
  }
}

void mouseDragged() {
  center_cell_offset_row -= (mouseY - pmouseY) / cell_height;
  center_cell_offset_col -= (mouseX - pmouseX) / cell_width;
}

void keyPressed() {
  if (key == ' ') {
    paused = !paused;
  }
  else if (key == 'a') {
    if (millis_per_update > 0) {
      --millis_per_update;
    }
  }
  else if (key == 'd') {
    ++millis_per_update;
  }
  else if (key == CODED) {
    if (keyCode == UP) {
      cell_width *= zoom_scale;
      cell_height *= zoom_scale;
    }
    else if (keyCode == DOWN) {
      cell_width /= zoom_scale;
      cell_height /= zoom_scale;
    }
  }
}
