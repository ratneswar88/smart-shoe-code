import 'dart:math';

/// Multi-class softmax linear classifier
class SoftmaxClassifier {
  late int nIn, nClasses;
  late List<double> W; // nClasses * nIn
  late List<double> b; // nClasses

  void init({required int nIn, required List<String> labels}) {
    this.nIn = nIn;
    nClasses = labels.length;
    final rnd = Random(42);
    W = List.generate(nClasses*nIn, (_) => (rnd.nextDouble()-0.5)*0.01);
    b = List.filled(nClasses, 0.0);
  }

  List<double> _matVec(List<double> w, List<double> x) {
    final out = List.filled(nClasses, 0.0);
    for (int k=0;k<nClasses;k++) {
      double s=b[k];
      final off = k*nIn;
      for (int i=0;i<nIn;i++) { s += w[off+i]*x[i]; }
      out[k]=s;
    }
    return out;
  }

  static List<double> _softmax(List<double> z) {
    final m = z.reduce(max);
    final ex = z.map((v)=>mathExp(v-m)).toList();
    final s = ex.reduce((p,c)=>p+c);
    return ex.map((v)=>v/s).toList();
  }

  static double mathExp(double x)=>exp(x);

  void fit(List<List<double>> X, List<int> y,
      {int epochs=30, double lr=0.05, double l2=1e-4, int batch=64}) {

    for (int ep=0; ep<epochs; ep++) {
      int i=0;
      while (i < X.length) {
        final j = (i+batch < X.length) ? i+batch : X.length;
        // grads
        final gW = List.filled(W.length, 0.0);
        final gb = List.filled(b.length, 0.0);

        for (int n=i;n<j;n++) {
          final x = X[n];
          final logits = _matVec(W, x);
          final p = _softmax(logits);
          for (int k=0;k<nClasses;k++) {
            final t = (k==y[n]) ? 1.0 : 0.0;
            final diff = (p[k] - t);
            gb[k] += diff;
            final off = k*nIn;
            for (int d=0; d<nIn; d++) {
              gW[off+d] += diff * x[d];
            }
          }
        }
        // apply
        for (int k=0;k<nClasses;k++) { b[k] -= lr*(gb[k]/(j-i)); }
        for (int idx=0; idx<W.length; idx++) {
          W[idx] -= lr*((gW[idx]/(j-i)) + l2*W[idx]);
        }
        i=j;
      }
    }
  }

  List<double> predictProba(List<double> x) => _softmax(_matVec(W,x));

  int predict(List<double> x) {
    final p = predictProba(x);
    int arg=0; double best=p[0];
    for (int k=1;k<p.length;k++) if (p[k]>best){best=p[k];arg=k;}
    return arg;
  }
}

/// Multi-label: independent logistic unit per label (sigmoid)
class MultiLabelLogistic {
  late int nIn, nLabels;
  late List<double> W; // nLabels * nIn
  late List<double> b; // nLabels

  void init({required int nIn, required int nLabels}) {
    this.nIn = nIn; this.nLabels = nLabels;
    final rnd = Random(7);
    W = List.generate(nLabels*nIn, (_) => (rnd.nextDouble()-0.5)*0.01);
    b = List.filled(nLabels, 0.0);
  }

  static double _sig(double z)=>1.0/(1.0+exp(-z));

  List<double> _logits(List<double> x) {
    final out = List.filled(nLabels, 0.0);
    for (int k=0;k<nLabels;k++) {
      double s = b[k];
      final off = k*nIn;
      for (int i=0;i<nIn;i++) s += W[off+i]*x[i];
      out[k]=s;
    }
    return out;
  }

  void fit(List<List<double>> X, List<List<int>> Y,
      {int epochs=30, double lr=0.05, double l2=1e-4, int batch=64}) {
    for (int ep=0; ep<epochs; ep++) {
      int i=0;
      while (i<X.length) {
        final j=(i+batch<X.length)?i+batch:X.length;
        final gW = List.filled(W.length,0.0);
        final gb = List.filled(b.length,0.0);
        for (int n=i;n<j;n++) {
          final z = _logits(X[n]);
          for (int k=0;k<nLabels;k++) {
            final p = _sig(z[k]);
            final diff = (p - (Y[n][k].toDouble()));
            gb[k] += diff;
            final off=k*nIn;
            for (int d=0; d<nIn; d++) gW[off+d] += diff*X[n][d];
          }
        }
        for (int k=0;k<nLabels;k++) b[k] -= lr*(gb[k]/(j-i));
        for (int idx=0; idx<W.length; idx++) {
          W[idx] -= lr*((gW[idx]/(j-i)) + l2*W[idx]);
        }
        i=j;
      }
    }
  }

  List<double> predictProba(List<double> x) {
    final z=_logits(x);
    return List.generate(nLabels, (k)=>_sig(z[k]));
  }
}
