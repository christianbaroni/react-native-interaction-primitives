package com.rninteractionprimitives;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import com.facebook.react.bridge.BridgeReactContext;
import com.facebook.react.uimanager.DisplayMetricsHolder;
import com.facebook.react.uimanager.ThemedReactContext;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;

public final class RNSideDrawerViewVerification extends Instrumentation {
  private int failures;
  private int casesRun;
  private String selectedCase;
  private final StringBuilder output = new StringBuilder();
  private ThemedReactContext reactContext;
  private interface Case {
    void run() throws Exception;
  }

  @Override
  public void onCreate(Bundle arguments) {
    super.onCreate(arguments);
    selectedCase = arguments == null ? null : arguments.getString("case");
    start();
  }

  @Override
  public void onStart() {
    runOnMainSync(() -> {
      try {
        Context context = getTargetContext();
        DisplayMetricsHolder.initDisplayMetricsIfNotInitialized(context);
        reactContext = new ThemedReactContext(new BridgeReactContext(context), context, "DrawerVerification", 1);
        runCase("first admitted position is independent of child dispatch", this::firstMovePosition);
        runCase("interruption preserves the last applied frame", this::firstInterruptedMove);
        runCase("batched and unbatched flick preserve identical native input", this::batchedFlick);
        runCase("tap does not interrupt settling", this::tapDuringSettling);
        runCase("active pointer replacement before admission", this::pointerBeforeAdmission);
        runCase("active pointer replacement after admission has no jump", this::pointerAfterAdmission);
        runCase("cross-axis input remains with child", this::verticalGesture);
        runCase("cancel and command release raw gesture ownership", this::cancelAndCommand);
      } catch (Throwable failure) {
        failures++;
        output.append("HARNESS ERROR ").append(android.util.Log.getStackTraceString(failure)).append('\n');
      }
    });
    if (casesRun == 0) {
      failures++;
      output.append("HARNESS ERROR no test case selected\n");
    }
    Bundle results = new Bundle();
    results.putString("stream", output + "\ncases=" + casesRun + "\nfailures=" + failures + "\n");
    results.putInt("failures", failures);
    finish(failures == 0 ? Activity.RESULT_OK : Activity.RESULT_CANCELED, results);
  }

  private void runCase(String label, Case test) {
    if (selectedCase != null && !label.contains(selectedCase)) return;
    casesRun++;
    try {
      test.run();
      output.append("PASS ").append(label).append('\n');
    } catch (Throwable failure) {
      failures++;
      output.append("FAIL ").append(label).append(": ").append(failure).append('\n');
    }
  }

  private final class Fixture implements AutoCloseable {
    final FrameLayout host = new FrameLayout(reactContext);
    final RNSideDrawerView drawer = new RNSideDrawerView(reactContext);
    final RNSideDrawerContentView content = new RNSideDrawerContentView(reactContext);
    final View leaf = new View(reactContext);
    final List<Integer> leafActions = new ArrayList<>();
    final long start = SystemClock.uptimeMillis();

    Fixture() {
      host.setId(101);
      drawer.setId(105);
      content.setId(107);
      leaf.setId(109);
      leaf.setOnTouchListener((v, e) -> { leafActions.add(e.getActionMasked()); return true; });
      host.addView(drawer, new FrameLayout.LayoutParams(600, 800));
      drawer.setDrawerWidthPx(300f);
      drawer.setContentCornerRadiusPx(0f);
      RNSideDrawerPanelView panel = new RNSideDrawerPanelView(reactContext);
      panel.setId(111);
      drawer.addDrawerSlot(panel, 0);
      drawer.addDrawerSlot(content, 1);
      content.addReactChild(leaf, 0);
      int width = View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY);
      int height = View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY);
      host.measure(width, height);
      host.layout(0, 0, 600, 800);
      leaf.measure(width, height);
      leaf.layout(0, 0, 600, 800);
    }

    void send(int action, long offset, float x, float y) {
      MotionEvent event = MotionEvent.obtain(start, start + offset, action, x, y, 0);
      dispatch(event);
    }

    void dispatch(MotionEvent event) {
      try {
        host.dispatchTouchEvent(event);
      } finally {
        event.recycle();
      }
    }

    void multi(int action, long offset, int[] ids, float[] xs) {
      MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[ids.length];
      MotionEvent.PointerCoords[] coordinates = new MotionEvent.PointerCoords[ids.length];
      for (int i = 0; i < ids.length; i++) {
        properties[i] = new MotionEvent.PointerProperties();
        properties[i].id = ids[i];
        properties[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
        coordinates[i] = new MotionEvent.PointerCoords();
        coordinates[i].x = xs[i];
        coordinates[i].y = 50f;
        coordinates[i].pressure = 1f;
        coordinates[i].size = 1f;
      }
      dispatch(MotionEvent.obtain(start, start + offset, action, ids.length, properties, coordinates,
          0, 0, 1f, 1f, 0, 0, android.view.InputDevice.SOURCE_TOUCHSCREEN, 0));
    }

    @Override
    public void close() {
      drawer.prepareForRemoval();
    }
  }

  private void firstMovePosition() throws Exception {
    float[] positions = new float[2];
    boolean[] canceledTargets = new boolean[2];
    for (int childOwns = 0; childOwns < 2; childOwns++) {
      try (Fixture f = new Fixture()) {
        final boolean consumes = childOwns == 1;
        f.leaf.setOnTouchListener((v, e) -> { f.leafActions.add(e.getActionMasked()); return consumes; });
        f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
        f.send(MotionEvent.ACTION_MOVE, 10, 240f, 50f);
        positions[childOwns] = ((Number) field(f.drawer, "revealPx")).floatValue();
        View presentation = (View) field(f.drawer, "contentPresentationView");
        require(presentation.getTranslationX() == 200f, "admission did not render the accepted position");
        output.append("  firstMove childOwns=").append(consumes).append(" reveal=")
            .append(positions[childOwns]).append(" translation=").append(presentation.getTranslationX())
            .append(" phase=").append(field(f.drawer, "phase")).append(" childActions=")
            .append(f.leafActions).append('\n');
        f.send(MotionEvent.ACTION_CANCEL, 15, 240f, 50f);
        canceledTargets[childOwns] = (boolean) field(f.drawer, "targetOpen");
        output.append("  cancel targetOpen=").append(canceledTargets[childOwns]).append('\n');
      }
    }
    require(positions[0] == 200f && positions[1] == 200f, "admitted position depends on original touch target");
    require(canceledTargets[0] && canceledTargets[1], "cancellation uses stale admission position");
  }

  private void firstInterruptedMove() throws Exception {
    try (Fixture f = new Fixture()) {
      f.drawer.open(true);
      long start = (long) field(f.drawer, "transitionStartTimeNanos");
      java.lang.reflect.Method frame = f.drawer.getClass().getDeclaredMethod("updateTransitionFrame", long.class);
      frame.setAccessible(true);
      frame.invoke(f.drawer, start + 50_000_000L);
      float applied = ((Number) field(f.drawer, "revealPx")).floatValue();
      require(applied > 0f && applied < 300f, "frame setup did not produce an interior settling position");
      f.send(MotionEvent.ACTION_DOWN, 0, 240f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 10, 180f, 50f);
      float admitted = ((Number) field(f.drawer, "revealPx")).floatValue();
      f.send(MotionEvent.ACTION_MOVE, 20, 170f, 50f);
      float next = ((Number) field(f.drawer, "revealPx")).floatValue();
      output.append("  interrupted firstMove applied=").append(applied).append(" admitted=")
          .append(admitted).append(" next=").append(next).append('\n');
      require(admitted == applied, "interruption consumed pre-admission translation or advanced the frame");
      require(Math.abs(next - applied + 10f) < 0.001f, "interrupted drag did not follow later movement one-to-one");
    }
  }

  private void batchedFlick() throws Exception {
    double[] velocities = new double[2];
    boolean[] targets = new boolean[2];
    for (int batch = 0; batch < 2; batch++) {
      try (Fixture f = new Fixture()) {
        f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
        if (batch == 0) {
          f.send(MotionEvent.ACTION_MOVE, 10, 70f, 50f);
          f.send(MotionEvent.ACTION_MOVE, 20, 100f, 50f);
        } else {
          MotionEvent event = MotionEvent.obtain(f.start, f.start + 10, MotionEvent.ACTION_MOVE, 70f, 50f, 0);
          event.addBatch(f.start + 20, 100f, 50f, 1f, 1f, 0);
          f.dispatch(event);
        }
        f.send(MotionEvent.ACTION_UP, 25, 100f, 50f);
        velocities[batch] = ((Number) field(f.drawer, "transitionInitialVelocityPxPerSecond")).doubleValue();
        targets[batch] = (boolean) field(f.drawer, "targetOpen");
        output.append("  ").append(batch == 0 ? "unbatched" : "batched").append(" velocity=")
            .append(velocities[batch]).append(" targetOpen=").append(targets[batch])
            .append(" childActions=").append(f.leafActions).append('\n');
        require(f.leafActions.contains(MotionEvent.ACTION_CANCEL), "child was not canceled by actual interception");
      }
    }
    require(targets[0] && targets[1], "same opening flick selected different/closed targets");
    require(velocities[0] > 0.0 && Math.abs(velocities[0] - velocities[1]) < 0.001,
        "same samples changed admitted velocity across batching");
  }

  private void pointerBeforeAdmission() throws Exception {
    try (Fixture f = new Fixture()) {
      f.multi(MotionEvent.ACTION_DOWN, 0, new int[] {0}, new float[] {40});
      f.multi(MotionEvent.ACTION_POINTER_DOWN | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 5,
          new int[] {0, 1}, new float[] {40, 90});
      f.multi(MotionEvent.ACTION_POINTER_UP, 10, new int[] {0, 1}, new float[] {40, 90});
      f.multi(MotionEvent.ACTION_MOVE, 15, new int[] {1}, new float[] {95});
      require(!(boolean) field(f.drawer, "isDragging"), "replacement pointer admitted below touch slop");
      f.multi(MotionEvent.ACTION_MOVE, 20, new int[] {1}, new float[] {140});
      output.append("  pointerBefore phase=").append(field(f.drawer, "phase"))
          .append(" activePointer=").append(field(f.drawer, "activePointerId"))
          .append(" childActions=").append(f.leafActions).append('\n');
      require((boolean) field(f.drawer, "isDragging"), "remaining pointer could not admit drawer gesture");
      require((int) field(f.drawer, "activePointerId") == 1, "active pointer did not change");
      f.multi(MotionEvent.ACTION_MOVE, 25, new int[] {1}, new float[] {150});
      float reveal = ((Number) field(f.drawer, "revealPx")).floatValue();
      require(Math.abs(reveal - 60f) < 0.001f, "replacement pointer inherited another finger's drag origin");
    }
  }

  private void pointerAfterAdmission() throws Exception {
    try (Fixture f = new Fixture()) {
      f.multi(MotionEvent.ACTION_DOWN, 0, new int[] {0}, new float[] {40});
      f.multi(MotionEvent.ACTION_MOVE, 10, new int[] {0}, new float[] {90});
      f.multi(MotionEvent.ACTION_MOVE, 20, new int[] {0}, new float[] {110});
      float before = ((Number) field(f.drawer, "revealPx")).floatValue();
      f.multi(MotionEvent.ACTION_POINTER_DOWN | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 25,
          new int[] {0, 1}, new float[] {110, 200});
      f.multi(MotionEvent.ACTION_POINTER_UP, 30, new int[] {0, 1}, new float[] {110, 200});
      float replacement = ((Number) field(f.drawer, "revealPx")).floatValue();
      f.multi(MotionEvent.ACTION_MOVE, 40, new int[] {1}, new float[] {220});
      float after = ((Number) field(f.drawer, "revealPx")).floatValue();
      output.append("  pointerAfter reveal=").append(before).append('/').append(replacement)
          .append('/').append(after).append('\n');
      require(before == replacement && Math.abs(after - before - 20f) < 0.001f,
          "pointer replacement changed drag position or displacement");
    }
  }

  private void tapDuringSettling() throws Exception {
    try (Fixture f = new Fixture()) {
      f.drawer.open(false);
      f.drawer.close(true);
      long epoch = (long) field(f.drawer, "transitionStartTimeNanos");
      f.send(MotionEvent.ACTION_DOWN, 0, 400f, 50f);
      require((boolean) field(f.drawer, "transitionRunning"), "touch down paused the native transition");
      require((long) field(f.drawer, "transitionStartTimeNanos") == epoch, "touch down restarted settling");
      f.send(MotionEvent.ACTION_UP, 10, 400f, 50f);
      require((boolean) field(f.drawer, "transitionRunning"), "touch up stopped the native transition");
      require((long) field(f.drawer, "transitionStartTimeNanos") == epoch, "touch up restarted settling");
      require(field(f.drawer, "phase").toString().equals("Settling"), "tap changed settling phase");
      require(f.leafActions.contains(MotionEvent.ACTION_DOWN) && f.leafActions.contains(MotionEvent.ACTION_UP),
          "tap did not reach the content child");
    }
  }

  private void verticalGesture() throws Exception {
    try (Fixture f = new Fixture()) {
      f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 10, 45f, 100f);
      f.send(MotionEvent.ACTION_UP, 20, 45f, 100f);
      require(!f.leafActions.contains(MotionEvent.ACTION_CANCEL), "vertical gesture canceled child");
      require(f.leafActions.contains(MotionEvent.ACTION_UP), "vertical gesture lost child end");
      require(field(f.drawer, "phase").toString().equals("Closed"), "vertical gesture changed drawer state");
    }
  }

  private void cancelAndCommand() throws Exception {
    try (Fixture f = new Fixture()) {
      f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 10, 90f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 20, 110f, 50f);
      f.send(MotionEvent.ACTION_CANCEL, 25, 110f, 50f);
      require(!(boolean) field(f.drawer, "isDragging"), "cancel retained dragging");
      require((int) field(f.drawer, "activePointerId") == -1, "cancel retained pointer");
      f.drawer.close(false);
      f.send(MotionEvent.ACTION_DOWN, 30, 40f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 40, 90f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 50, 110f, 50f);
      f.drawer.open(false);
      require(!(boolean) field(f.drawer, "isDragging"), "command retained dragging");
      f.send(MotionEvent.ACTION_UP, 55, 110f, 50f);
      require((int) field(f.drawer, "activePointerId") == -1, "command end retained pointer");
    }
  }

  private static Object field(Object owner, String name) throws Exception {
    Field field = owner.getClass().getDeclaredField(name);
    field.setAccessible(true);
    return field.get(owner);
  }

  private static void require(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }
}
