import Foundation
import simd
import Accelerate

fileprivate let sqrt_3: Float = 1.73205080756887729352744634151

extension matrix_double3x3 {
    // Reduces a symmetric 3x3 matrix to tridiagonal form by applying
    // (unitary) Householder transformations:
    //            [ d[0]  e[0]       ]
    //    A = Q . [ e[0]  d[1]  e[1] ] . Q^T
    //            [       e[1]  d[2] ]
    // The function accesses only the diagonal and upper triangular parts of
    // A. The access is read-only.
    // ---------------------------------------------------------------------------
    var tridiagonal: (double3x3, double3, double2) {
        var d = double3.zero
        var e = double2.zero
        var u = double3.zero
        var q = double3.zero

        var Q = matrix_identity_double3x3

        // Bring first row and column to the desired form
        let h = sqr(self[1, 0] + sqr(self[2, 0]))
        let g = self[1, 0] > 0 ? -sqrt(h) : sqrt(h)

        e.x = g
        var f = g * self[1, 0]
        u.y = self[1,0] - g
        u.z = self[2,0]

        var omega = h - f
        if omega > 0.0 {
            omega = 1.0 / omega
            var K = 0.0
            for i in 1..<3 {
                f = self[i, 1] * u[1] + self[2, 1] * u[2]
                q[i] = omega * f                  // p
                K   += u[i] * f                   // u* A u
            }
            K *= 0.5 * sqr(omega)

            for i in 1..<3 {
                q[i] = q[i] - K * u[i]
            }

            d[0] = self[0, 0]
            d[1] = self[1, 1] - 2.0*q[1]*u[1]
            d[2] = self[2, 2] - 2.0*q[2]*u[2]

            // Store inverse Householder transformation in Q
            for j in 1..<3 {
                f = omega * u[j]
                for i in 1..<3 {
                    Q[j, i] = Q[j, i] - f*u[i]
                }
            }

            // Calculate updated A[1][2] and store it in e[1]
            e[1] = self[2, 1] - q[1]*u[2] - u[1]*q[2]
        } else {
            for i in 0..<3 {
                d[i] = self[i, i]
            }
            e[1] = self[2, 1]
        }

        return (Q, d, e)
    }

    // Calculates the eigenvalues and normalized eigenvectors of a symmetric 3x3
    // matrix A using the QL algorithm with implicit shifts, preceded by a
    // Householder reduction to tridiagonal form.
    var eigen_ql: (double3, double3x3)? {
        var g, r, p, f, b, s, c, t: Double // Intermediate storage
        var (Q, w, e_) = self.tridiagonal
        var e = double3(e_.x, e_.y, 0)

        // Calculate eigensystem of the remaining real symmetric tridiagonal matrix
        // with the QL method
        //
        // Loop over all off-diagonal elements

        for l in 0..<2 {
            var nIter = 0
            while true {
                // Check for convergence and exit iteration loop if off-diagonal
                // element e(l) is zero

                var m = l
                while m <= 1 {
                    g = abs(w[m])+abs(w[m+1])
                    if abs(e[m]) + g == g {
                        break
                    }
                    m += 1
                }
                if m == l {
                    break
                }

                if nIter >= 30 {
                    return nil
                }
                nIter += 1

                // Calculate g = d_m - k
                g = (w[l+1] - w[l]) / (e[l] + e[l])
                r = sqrt(sqr(g) + 1.0)
                if g > 0 {
                    g = w[m] - w[l] + e[l]/(g + r)
                } else {
                    g = w[m] - w[l] + e[l]/(g - r)
                }

                c = 1.0; s = 1.0
                p = 0.0

                var i = m-1
                while i >= l {
                    f = s * e[i]
                    b = c * e[i]
                    if abs(f) > abs(g) {
                        c      = g / f
                        r      = sqrt(sqr(c) + 1.0)
                        e[i+1] = f * r
                        s      = 1.0/r
                        c      *= s
                    } else {
                        s      = f / g
                        r      = sqrt(sqr(s) + 1.0)
                        e[i+1] = g * r
                        c = 1.0/r
                        s     *= c
                    }

                    g = w[i+1] - p
                    r = (w[i] - g)*s + 2.0*c*b
                    p = s * r
                    w[i+1] = g + p
                    g = c*r - b

                    // Form eigenvectors
                    for k in 0..<3 {
                        t = Q[i+1, k]
                        Q[i+1, k] = s*Q[i, k] + c*t
                        Q[i, k]   = c*Q[i, k] - s*t
                    }
                    i -= 1
                }
                w[l] -= p
                e[l]  = g
                e[m]  = 0.0
            }
        }

        return (w, Q)
    }

}

extension matrix_float3x3 {
    // Calculates the eigenvalues of a symmetric 3x3 matrix A using Cardano's
    // analytical algorithm.
    var eigenvalues_analytical: float3 {
        // Determine coefficients of characteristic poynomial. We write
        //       | a   d   f  |
        //  A =  | d*  b   e  |
        //       | f*  e*  c  |
        let de = self[1, 0] * self[2, 1]                                 // d * e
        let dd = sqr(self[1, 0])                                         // d^2
        let ee = sqr(self[2, 1])                                         // e^2
        let ff = sqr(self[2, 0])                                         // f^2
        let m  = self[0, 0] + self[1, 1] + self[2, 2]
        // a*b + a*c + b*c - d^2 - e^2 - f^2
        let c1 = (self[0, 0]*self[1, 1] + self[0, 0]*self[2, 2] + self[1, 1]*self[2, 2]) -
            (dd + ee + ff)
        // c*d^2 + a*e^2 + b*f^2 - a*b*c - 2*f*d*e)
        let c0 = self[2, 2]*dd + self[0, 0]*ee + self[1, 1]*ff - self[0, 0]*self[1, 1]*self[2, 2]
            - 2.0 * self[2, 0]*de

        let p = sqr(m) - 3.0*c1
        let q = m*(p - (3.0/2.0)*c1) - (27.0/2.0)*c0
        let sqrt_p = sqrt(abs(p))

        var phi = 27.0 * ( 0.25*sqr(c1)*(p - c1) + c0*(q + 27.0/4.0*c0))
        phi = (1.0/3.0) * atan2(sqrt(abs(phi)), q)

        let c = sqrt_p*cos(phi)
        let s = (1.0/sqrt_3)*sqrt_p*sin(phi)

        var w1  = (1.0/3.0)*(m - c)
        let w2  = w1 + s
        let w0  = w1 + c
        w1 -= s

        return float3(w0, w1, w2)
    }

    var eigen_analytical: (float3, float3x3)? {
        var Q = float3x3.init(0)
        let w = self.eigenvalues_analytical
        let abs_w = abs(w)

        var t = abs_w.x
        var u = abs_w.y
        if u > abs_w.x {
            t = abs_w.x
        }
        u = abs_w.z
        if u > t {
            t = u
        }
        if t < 1.0 {
            u = t
        } else {
            u = sqr(t)
        }
        let error = 256.0 * Float.ulpOfOne * sqr(u)

        // Calculate first eigenvector by the formula
        //   v[0] = (A - w[0]).e1 x (A - w[0]).e2
        Q[0] = cross(self[0] - float3(w.x, 0, 0), self[1] - float3(0, w.x, 0))
        var norm = dot(Q[0], Q[0])

        // If vectors are nearly linearly dependent, or if there might have
        // been large cancellations in the calculation of A[i][i] - w[0], fall
        // back to QL algorithm
        // Note that this simultaneously ensures that multiple eigenvalues do
        // not cause problems: If w[0] = w[1], then A - w[0] * I has rank 1,
        // i.e. all columns of A - w[0] * I are linearly dependent.
        if norm <= error {
            return self.eigen_ql
        } else {                      // This is the standard branch
            norm = sqrt(1.0 / norm)
            Q[0] *= norm
        }

        // Calculate second eigenvector by the formula
        //   v[1] = (A - w[1]).e1 x (A - w[1]).e2
        Q[1] = cross(self[0] - float3(w.y, 0, 0), self[1] - float3(0, w.y, 0))

        norm = dot(Q[1], Q[1])
        if norm <= error {
            return self.eigen_ql
        } else {
            norm = sqrt(1.0 / norm)
            Q[1] *= norm
        }

        // Calculate third eigenvector according to
        //   v[2] = v[0] x v[1]
        Q[2] = cross(Q[0], Q[1])

        return (w, Q)
    }

    var eigen_ql: (float3, float3x3)? {
        guard let (eigenvalues, eigenvectors) = double3x3(self).eigen_ql else {
            return nil
        }
        return (float3(eigenvalues), float3x3(eigenvectors))
    }
}