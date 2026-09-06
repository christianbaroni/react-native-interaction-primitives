package com.rninteractionprimitives;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import com.facebook.react.bridge.BridgeReactContext;
import com.facebook.react.bridge.JavaOnlyArray;
import com.facebook.react.bridge.JavaOnlyMap;
import com.facebook.react.uimanager.DisplayMetricsHolder;
import com.facebook.react.uimanager.ReactStylesDiffMap;
import com.facebook.react.uimanager.TouchTargetHelper;
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
        for (String mode : new String[] {"auto", "none", "box-only", "box-none"}) {
          runCase("native pointerEvents=" + mode, () -> pointerEvents(mode));
        }
        runCase("box-none preserves child exclusion of ancestors", this::childKeepsAncestorExclusion);
        for (String mode : new String[] {"none", "box-only"}) {
          runCase("child exclusion ends when pointerEvents=" + mode, () -> forbiddenChildLosesExclusion(mode));
        }
        runCase("box-only admits the first move of a child-owned contact", this::boxOnlyDuringAdmission);
        for (String mode : new String[] {"none", "box-none"}) {
          runCase("active drag cancellation, fresh input and null reset for " + mode,
              () -> pointerEventsCancelsDrag(mode));
        }
        runCase("gestureEnabled=false still consumes permitted self touches", this::disabledGestureConsumesTouch);
        runCase("box-none keeps a horizontal pan with the child", this::boxNoneChildPan);
        runCase("generic scroll follows pointerEvents child policy", this::pointerEventsGenericScroll);
        runCase("pointerEvents adapter forwards ordinary props and commands", this::managerForwarding);
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

  private final class InterceptingHost extends FrameLayout {
    boolean interceptMoves;

    InterceptingHost() {
      super(reactContext);
    }

    @Override
    public boolean onInterceptTouchEvent(MotionEvent event) {
      return interceptMoves && event.getActionMasked() == MotionEvent.ACTION_MOVE
          || super.onInterceptTouchEvent(event);
    }
  }

  private final class Fixture implements AutoCloseable {
    final InterceptingHost host = new InterceptingHost();
    final View behind = new View(reactContext);
    final RNSideDrawerViewManager manager = new RNSideDrawerViewManager();
    final RNSideDrawerView drawer = new RNSideDrawerView(reactContext);
    final RNSideDrawerContentView content = new RNSideDrawerContentView(reactContext);
    final View leaf = new View(reactContext);
    final List<Integer> leafActions = new ArrayList<>();
    final List<Integer> behindActions = new ArrayList<>();
    final long start = SystemClock.uptimeMillis();

    Fixture() {
      host.setId(101);
      behind.setId(103);
      drawer.setId(105);
      content.setId(107);
      leaf.setId(109);
      leaf.setOnTouchListener((v, e) -> { leafActions.add(e.getActionMasked()); return true; });
      behind.setOnTouchListener((v, e) -> { behindActions.add(e.getActionMasked()); return true; });
      host.addView(behind, new FrameLayout.LayoutParams(600, 800));
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

    void props(Object... values) {
      manager.updateProperties(drawer, new ReactStylesDiffMap(JavaOnlyMap.of(values)));
    }

    void childRequestsExclusiveTouch() {
      leaf.setOnTouchListener((v, event) -> {
        leafActions.add(event.getActionMasked());
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
          v.getParent().requestDisallowInterceptTouchEvent(true);
        }
        return true;
      });
    }

    boolean send(int action, long offset, float x, float y) {
      MotionEvent event = MotionEvent.obtain(start, start + offset, action, x, y, 0);
      return dispatch(event);
    }

    boolean dispatch(MotionEvent event) {
      try {
        return host.dispatchTouchEvent(event);
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
          0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0));
    }

    void scroll() {
      MotionEvent.PointerProperties pointer = new MotionEvent.PointerProperties();
      pointer.id = 0;
      pointer.toolType = MotionEvent.TOOL_TYPE_MOUSE;
      MotionEvent.PointerCoords position = new MotionEvent.PointerCoords();
      position.x = 40f;
      position.y = 50f;
      position.setAxisValue(MotionEvent.AXIS_VSCROLL, 1f);
      MotionEvent event = MotionEvent.obtain(start, start, MotionEvent.ACTION_SCROLL, 1,
          new MotionEvent.PointerProperties[] {pointer}, new MotionEvent.PointerCoords[] {position},
          0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_MOUSE, 0);
      try {
        host.dispatchGenericMotionEvent(event);
      } finally {
        event.recycle();
      }
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

  private void pointerEvents(String mode) throws Exception {
    try (Fixture f = new Fixture()) {
      f.props("pointerEvents", mode);
      int reactTarget = TouchTargetHelper.findTargetTagForTouch(40f, 50f, f.host);
      f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
      f.send(MotionEvent.ACTION_UP, 5, 40f, 50f);
      boolean leafTapped = f.leafActions.contains(MotionEvent.ACTION_UP);
      boolean behindTapped = f.behindActions.contains(MotionEvent.ACTION_UP);
      output.append("  ").append(mode).append(" reactTarget=").append(reactTarget)
          .append(" leafTapped=").append(leafTapped).append(" behindTapped=").append(behindTapped).append('\n');
      int expected = mode.equals("none") ? f.behind.getId()
          : mode.equals("box-only") ? f.drawer.getId() : f.leaf.getId();
      require(reactTarget == expected, "React hit target ignores pointerEvents");
      require(leafTapped == (mode.equals("auto") || mode.equals("box-none")), "native child tap ownership differs");
      require(behindTapped == mode.equals("none"), "native sibling tap ownership differs");
      if (mode.equals("none")) {
        f.send(MotionEvent.ACTION_DOWN, 10, 40f, 50f);
        f.send(MotionEvent.ACTION_MOVE, 20, 100f, 50f);
        require(!(boolean) field(f.drawer, "isDragging"), "pointerEvents=none still admits drawer drag");
      }
    }
  }

  private void childKeepsAncestorExclusion() throws Exception {
    for (boolean gestureEnabled : new boolean[] {true, false}) {
      try (Fixture f = new Fixture()) {
        f.props("gestureEnabled", gestureEnabled);
        f.childRequestsExclusiveTouch();
        f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
        f.host.interceptMoves = true;
        f.props("pointerEvents", "box-none");
        f.send(MotionEvent.ACTION_MOVE, 10, 140f, 50f);
        f.send(MotionEvent.ACTION_UP, 20, 140f, 50f);
        output.append("  box-none gestureEnabled=").append(gestureEnabled)
            .append(" childActions=").append(f.leafActions).append('\n');
        require(f.leafActions.contains(MotionEvent.ACTION_MOVE) && f.leafActions.contains(MotionEvent.ACTION_UP),
            "box-none revoked the child's exclusion of ancestor interception");
        require(!f.leafActions.contains(MotionEvent.ACTION_CANCEL), "permitted child was canceled by ancestor");
        require(!(boolean) field(f.drawer, "isDragging"), "box-none admitted the drawer");
      }
    }
  }

  private void forbiddenChildLosesExclusion(String mode) throws Exception {
    try (Fixture f = new Fixture()) {
      f.props("gestureEnabled", false);
      f.childRequestsExclusiveTouch();
      f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
      f.props("pointerEvents", mode);
      f.send(MotionEvent.ACTION_MOVE, 10, 140f, 50f);
      require(f.leafActions.contains(MotionEvent.ACTION_CANCEL), "forbidden child retained interception exclusion");
      f.send(MotionEvent.ACTION_UP, 20, 140f, 50f);
      require(!f.leafActions.contains(MotionEvent.ACTION_UP), "forbidden child received the old contact's release");
      require(f.behindActions.isEmpty(), "mode change invented a new sibling contact");
      f.leafActions.clear();
      f.send(MotionEvent.ACTION_DOWN, 30, 40f, 50f);
      f.send(MotionEvent.ACTION_UP, 40, 40f, 50f);
      require(f.leafActions.isEmpty(), "fresh input reached a forbidden child");
      require(f.behindActions.contains(MotionEvent.ACTION_UP) == mode.equals("none"),
          "fresh input did not follow the new self policy");
    }
  }

  private void boxOnlyDuringAdmission() throws Exception {
    try (Fixture f = new Fixture()) {
      f.childRequestsExclusiveTouch();
      f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
      f.props("pointerEvents", "box-only");
      f.send(MotionEvent.ACTION_MOVE, 10, 240f, 50f);
      require((boolean) field(f.drawer, "isDragging"), "box-only interception bypassed gesture admission");
      require(((Number) field(f.drawer, "revealPx")).floatValue() == 200f,
          "box-only discarded the first intercepted move");
      View presentation = (View) field(f.drawer, "contentPresentationView");
      require(presentation.getTranslationX() == 200f, "box-only failed to render the admitted position");
      require(f.leafActions.contains(MotionEvent.ACTION_CANCEL), "box-only did not cancel the former child target");
    }
  }

  private void pointerEventsCancelsDrag(String mode) throws Exception {
    try (Fixture f = new Fixture()) {
      f.props("releaseOpenThreshold", 0.8);
      f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 10, 220f, 50f);
      require((boolean) field(f.drawer, "isDragging"), "setup did not admit a drawer drag");
      require(((Number) field(f.drawer, "revealPx")).floatValue() == 180f, "setup did not reach the threshold boundary");
      Object interaction = field(f.drawer, "activeInteraction");
      f.props("releaseOpenThreshold", 0.2);
      f.props("pointerEvents", mode);
      require(field(f.drawer, "phase").toString().equals("Settling"), "self exclusion did not settle the drag");
      require(!(boolean) field(f.drawer, "targetOpen"), "cancellation used the newly configured release threshold");
      require(field(f.drawer, "activeInteraction") == interaction, "cancellation replaced the admitted interaction snapshot");
      require(((Number) field(f.drawer, "transitionInitialVelocityPxPerSecond")).doubleValue() == 0.0,
          "cancellation retained release velocity");
      require(!(boolean) field(f.drawer, "isDragging") && !(boolean) field(f.drawer, "gestureEligible"),
          "self exclusion retained drawer gesture ownership");
      require((int) field(f.drawer, "activePointerId") == -1 && field(f.drawer, "velocityTracker") == null,
          "self exclusion retained raw contact tracking");
      f.send(MotionEvent.ACTION_MOVE, 20, 260f, 50f);
      require(((Number) field(f.drawer, "revealPx")).floatValue() == 180f, "forbidden contact moved the canceled drag");
      f.send(MotionEvent.ACTION_UP, 30, 260f, 50f);
      require(!(boolean) field(field(f.drawer, "nestedScrollCoordinator"), "nativeGestureActive"),
          "contact end retained React native gesture ownership");

      f.drawer.close(false);
      f.leafActions.clear();
      f.behindActions.clear();
      f.send(MotionEvent.ACTION_DOWN, 40, 40f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 50, 100f, 50f);
      f.send(MotionEvent.ACTION_UP, 60, 100f, 50f);
      require(!(boolean) field(f.drawer, "isDragging"), "fresh excluded input admitted a drawer drag");
      require(f.leafActions.contains(MotionEvent.ACTION_UP) == mode.equals("box-none"),
          "fresh input did not follow the new child policy");
      require(f.behindActions.contains(MotionEvent.ACTION_UP) == mode.equals("none"),
          "fresh input did not follow the new sibling policy");

      f.props("pointerEvents", null);
      require(TouchTargetHelper.findTargetTagForTouch(40f, 50f, f.host) == f.leaf.getId(),
          "null did not restore React's auto hit target");
      f.send(MotionEvent.ACTION_DOWN, 70, 40f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 80, 100f, 50f);
      require((boolean) field(f.drawer, "isDragging"), "fresh input after null reset could not admit a drawer drag");
      require(((Number) field(f.drawer, "revealPx")).floatValue() == 60f, "fresh drag inherited canceled contact position");
    }
  }

  private void disabledGestureConsumesTouch() throws Exception {
    for (String mode : new String[] {"auto", "box-only"}) {
      try (Fixture f = new Fixture()) {
        f.props("pointerEvents", mode, "gestureEnabled", false);
        f.leaf.setOnTouchListener((v, event) -> { f.leafActions.add(event.getActionMasked()); return false; });
        require(f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f), "disabled gesture rejected permitted self down");
        require(f.send(MotionEvent.ACTION_MOVE, 10, 140f, 50f), "disabled gesture rejected permitted self move");
        require(f.send(MotionEvent.ACTION_UP, 20, 140f, 50f), "disabled gesture rejected permitted self release");
        require(f.behindActions.isEmpty(), "permitted self contact leaked to a sibling");
        require(!f.leafActions.contains(MotionEvent.ACTION_UP), "declining or excluded child consumed the contact");
        if (mode.equals("box-only")) require(f.leafActions.isEmpty(), "box-only dispatched to a child");
        require(field(f.drawer, "phase").toString().equals("Closed"), "disabled gesture moved the drawer");
      }
    }
  }

  private void boxNoneChildPan() throws Exception {
    try (Fixture f = new Fixture()) {
      f.props("pointerEvents", "box-none");
      f.send(MotionEvent.ACTION_DOWN, 0, 40f, 50f);
      f.send(MotionEvent.ACTION_MOVE, 10, 240f, 50f);
      require(!(boolean) field(f.drawer, "isDragging"), "box-none admitted a horizontal drawer pan");
      f.send(MotionEvent.ACTION_UP, 20, 240f, 50f);
      require(f.leafActions.contains(MotionEvent.ACTION_MOVE) && f.leafActions.contains(MotionEvent.ACTION_UP),
          "box-none lost the child's horizontal pan");
      require(!f.leafActions.contains(MotionEvent.ACTION_CANCEL), "box-none canceled the permitted child");
      require(((Number) field(f.drawer, "revealPx")).floatValue() == 0f, "box-none pan changed drawer position");
    }
  }

  private void pointerEventsGenericScroll() {
    for (String mode : new String[] {"auto", "none", "box-only", "box-none"}) {
      try (Fixture f = new Fixture()) {
        f.props("pointerEvents", mode);
        int[] childScrolls = {0};
        f.leaf.setOnGenericMotionListener((v, event) -> {
          if (event.getActionMasked() == MotionEvent.ACTION_SCROLL) childScrolls[0]++;
          return true;
        });
        f.scroll();
        require(childScrolls[0] == (mode.equals("auto") || mode.equals("box-none") ? 1 : 0),
            "generic scroll ignored the child policy for " + mode);
      }
    }
  }

  private void managerForwarding() throws Exception {
    try (Fixture f = new Fixture()) {
      f.props("pointerEvents", "box-only", "gestureEnabled", false, "releaseOpenThreshold", 0.7, "opacity", 0.6);
      require(!f.drawer.getGestureEnabled() && f.drawer.getReleaseOpenThreshold() == 0.7,
          "pointerEvents adapter dropped generated properties");
      require(Math.abs(f.drawer.getAlpha() - 0.6f) < 0.000001f, "pointerEvents adapter dropped a base view property");
      String[] commands = {"open", "close", "toggle", "toggle"};
      for (int i = 0; i < commands.length; i++) {
        f.manager.receiveCommand(f.drawer, commands[i], JavaOnlyArray.of(false));
        boolean expectedOpen = i % 2 == 0;
        require(field(f.drawer, "phase").toString().equals(expectedOpen ? "Open" : "Closed"),
            "manager did not dispatch " + commands[i]);
        require(((Number) field(f.drawer, "revealPx")).floatValue() == (expectedOpen ? 300f : 0f),
            "manager command did not render its endpoint: " + commands[i]);
      }
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
