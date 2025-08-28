import 'dart:math';

class SoftmaxClassifier {
  late int nIn;
  late int nClasses;
  late List<double> W; // row-major [nClasses, nIn]
  late List<double> b; // [nClasses]

  void init(List<String> labels, int inputLen) {
    nClasses = labels.length;
    nIn = inputLen;
    final rnd = Random(1);
    W = List<double>.generate(nClasses * nIn, (_) => (rnd.nextDouble()-0.5)*0.01);
    b = List<double>.filled(nClasses, 0.0);
  }

  List<double> _matvec(List<double> w, List<double> x) {
    final out = List<double>.filled(nClasses, 0.0);
    for (int c=0;c<nClasses;c++) {
      double s = b[c];
      final rowOff = c*nIn;
      for (int i=0;i<nIn;i++) s += w[rowOff+i]*x[i];
      out[c] = s;
    }
    return out;
  }

  static List<double> _softmax(List<double> z) {
    final m = z.reduce(max);
    double sum=0.0; final e = List<double>.filled(z.length,0);
    for (int i=0;i<z.length;i++){e[i]=exp(z[i]-m); sum+=e[i];}
    for (int i=0;i<z.length;i++){e[i]/=sum;}
    return e;
  }

  int predictClass(List<double> x, {List<double>? outProba}) {
    final logits = _matvec(W, x);
    final p = _softmax(logits);
    if (outProba != null) {
      outProba.clear(); outProba.addAll(p);
    }
    int best=0; double mb=p[0];
    for (int i=1;i<p.length;i++){ if (p[i]>mb) {mb=p[i]; best=i;} }
    return best;
  }

  void fit(List<List<double>> X, List<int> y, {int epochs=20, double lr=0.05, double l2=1e-4, int batch=64}) {
    final n = X.length;
    for (int ep=0; ep<epochs; ep++) {
      for (int k=0;k<n;k+=batch) {
        final end = (k+batch<n)?k+batch:n;
        // grads
        final gW = List<double>.filled(nClasses*nIn, 0.0);
        final gb = List<double>.filled(nClasses, 0.0);
        for (int i=k;i<end;i++) {
          final xi = X[i];
          final pi = _softmax(_matvec(W, xi));
          for (int c=0;c<nClasses;c++) {
            final yc = (y[i]==c)?1.0:0.0;
            final diff = (pi[c]-yc);
            gb[c]+=diff;
            final rowOff = c*nIn;
            for (int j=0;j<nIn;j++) gW[rowOff+j]+=diff*xi[j];
          }
        }
        // apply l2
        for (int idx=0; idx<W.length; idx++) gW[idx] += l2*W[idx];
        // step
        final m = (end-k).toDouble();
        for (int idx=0; idx<W.length; idx++) W[idx] -= lr*(gW[idx]/m);
        for (int c=0;c<nClasses;c++) b[c] -= lr*(gb[c]/m);
      }
    }
  }
}
