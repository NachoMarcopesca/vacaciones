const fs = require("fs");
const path = require("path");
const express = require("express");
const admin = require("firebase-admin");

const PORT = process.env.PORT || 8080;
const ALLOWED_DOMAIN = process.env.ALLOWED_DOMAIN || "marcopescaimport.com";
const DEFAULT_ANNUAL_DAYS = Number(process.env.DEFAULT_ANNUAL_DAYS || "22");

const REQUESTS_COLLECTION = "requests";
const BALANCES_COLLECTION = "vacation_balances";
const HOLIDAYS_COLLECTION = "holidays";
const DEPARTMENTS_COLLECTION = "departments";

admin.initializeApp();
const db = admin.firestore();

const usersPath = path.join(__dirname, "users.json");
let usersList = [];
try {
  const raw = fs.readFileSync(usersPath, "utf-8");
  usersList = JSON.parse(raw);
} catch (err) {
  console.error("No se pudo leer users.json", err);
}

const usersByEmail = new Map(usersList.map((u) => [u.email.toLowerCase(), u]));

const app = express();
app.use(express.json({ limit: "1mb" }));

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type"
  );
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, OPTIONS");
  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }
  next();
});

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.get("/me", authMiddleware, (req, res) => {
  res.json({
    uid: req.user.uid,
    email: req.user.email,
    role: req.user.role,
    departamentoId: req.user.departamentoId || null,
    displayName: req.user.displayName || null,
  });
});

app.get("/requests", authMiddleware, async (req, res) => {
  try {
    const { user } = req;
    const requestedUserId = normalizeText(req.query.userId);
    const requestedDept = normalizeText(req.query.departamentoId);
    const status = normalizeText(req.query.status);

    let query = db.collection(REQUESTS_COLLECTION);

    if (user.role === "empleado") {
      query = query.where("userId", "==", user.uid);
    } else if (user.role === "responsable") {
      query = query.where("departamentoId", "==", user.departamentoId || "");
    } else if (user.role === "responsable_general" || user.role === "admin") {
      if (requestedUserId) {
        query = query.where("userId", "==", requestedUserId);
      } else if (requestedDept) {
        query = query.where("departamentoId", "==", requestedDept);
      }
    }

    if (status) {
      query = query.where("estado", "==", status);
    }

    const snapshot = await query.limit(500).get();
    const items = snapshot.docs
      .map((doc) => mapRequestDoc(doc))
      .sort((a, b) => {
        const ad = Date.parse(a.createdAt || "") || 0;
        const bd = Date.parse(b.createdAt || "") || 0;
        return bd - ad;
      });

    const itemsWithEstimates = await Promise.all(
      items.map(async (item) => {
        if (item.estado === "pendiente") {
          const start = parseDateInput(item.fechaInicioStr);
          const end = parseDateInput(item.fechaFinStr);
          if (start && end) {
            item.diasEstimados = await countConsumableDays(start, end);
          }
        }
        return item;
      })
    );

    res.json({ items: itemsWithEstimates });
  } catch (err) {
    console.error("requests_list_error", err);
    res.status(500).json({ error: "requests_list_error" });
  }
});

app.post("/requests", authMiddleware, async (req, res) => {
  try {
    if (req.user.role !== "empleado") {
      return res.status(403).json({ error: "forbidden" });
    }

    const payload = req.body || {};
    const start = parseDateInput(payload.fechaInicio);
    const end = parseDateInput(payload.fechaFin);
    if (!start || !end) {
      return res.status(400).json({ error: "invalid_dates" });
    }
    if (start > end) {
      return res.status(400).json({ error: "invalid_range" });
    }

    const overlap = await hasOverlap(req.user.uid, start, end, null);
    if (overlap) {
      return res.status(400).json({ error: "overlap" });
    }

    const docData = {
      userId: req.user.uid,
      userEmail: req.user.email,
      userDisplayName: req.user.displayName || null,
      departamentoId: req.user.departamentoId || null,
      tipo: "vacaciones",
      fechaInicio: admin.firestore.Timestamp.fromDate(start),
      fechaFin: admin.firestore.Timestamp.fromDate(end),
      fechaInicioStr: toDateKey(start),
      fechaFinStr: toDateKey(end),
      estado: "pendiente",
      aprobadorId: null,
      fechaAprobacion: null,
      notas: normalizeText(payload.notas) || null,
      diasConsumidos: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const docRef = await db.collection(REQUESTS_COLLECTION).add(docData);
    res.json({ id: docRef.id });
  } catch (err) {
    console.error("requests_create_error", err);
    res.status(500).json({ error: "requests_create_error" });
  }
});

app.patch("/requests/:id", authMiddleware, async (req, res) => {
  try {
    const docRef = db.collection(REQUESTS_COLLECTION).doc(req.params.id);
    const doc = await docRef.get();
    if (!doc.exists) {
      return res.status(404).json({ error: "not_found" });
    }

    const data = doc.data() || {};
    if (req.user.role === "empleado" && data.userId !== req.user.uid) {
      return res.status(403).json({ error: "forbidden" });
    }

    const start = parseDateInput(req.body?.fechaInicio || data.fechaInicioStr);
    const end = parseDateInput(req.body?.fechaFin || data.fechaFinStr);
    if (!start || !end) {
      return res.status(400).json({ error: "invalid_dates" });
    }
    if (start > end) {
      return res.status(400).json({ error: "invalid_range" });
    }

    const overlap = await hasOverlap(
      data.userId,
      start,
      end,
      doc.id
    );
    if (overlap) {
      return res.status(400).json({ error: "overlap" });
    }

    const updates = {
      fechaInicio: admin.firestore.Timestamp.fromDate(start),
      fechaFin: admin.firestore.Timestamp.fromDate(end),
      fechaInicioStr: toDateKey(start),
      fechaFinStr: toDateKey(end),
      notas: normalizeText(req.body?.notas) || data.notas || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (data.estado === "aprobada") {
      const consumed = Number(data.diasConsumidos || 0);
      if (consumed > 0) {
        await adjustBalance(data.userId, -consumed);
      }
      updates.estado = "pendiente";
      updates.aprobadorId = null;
      updates.fechaAprobacion = null;
      updates.diasConsumidos = 0;
    }

    await docRef.update(updates);
    res.json({ ok: true });
  } catch (err) {
    console.error("requests_update_error", err);
    res.status(500).json({ error: "requests_update_error" });
  }
});

app.post("/requests/:id/approve", authMiddleware, async (req, res) => {
  try {
    const docRef = db.collection(REQUESTS_COLLECTION).doc(req.params.id);
    const doc = await docRef.get();
    if (!doc.exists) {
      return res.status(404).json({ error: "not_found" });
    }

    const data = doc.data() || {};
    if (!canApprove(req.user, data)) {
      return res.status(403).json({ error: "forbidden" });
    }
    if (data.estado !== "pendiente") {
      return res.status(400).json({ error: "invalid_state" });
    }

    const start = timestampToDate(data.fechaInicio, data.fechaInicioStr);
    const end = timestampToDate(data.fechaFin, data.fechaFinStr);
    if (!start || !end) {
      return res.status(400).json({ error: "invalid_dates" });
    }

    const overlap = await hasOverlap(data.userId, start, end, doc.id);
    if (overlap) {
      return res.status(400).json({ error: "overlap" });
    }

    const diasConsumidos = await countConsumableDays(start, end);
    await adjustBalance(data.userId, diasConsumidos);

    await docRef.update({
      estado: "aprobada",
      aprobadorId: req.user.email,
      fechaAprobacion: admin.firestore.FieldValue.serverTimestamp(),
      diasConsumidos,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ ok: true, diasConsumidos });
  } catch (err) {
    console.error("requests_approve_error", err);
    res.status(500).json({ error: "requests_approve_error" });
  }
});

app.post("/requests/:id/reject", authMiddleware, async (req, res) => {
  try {
    const docRef = db.collection(REQUESTS_COLLECTION).doc(req.params.id);
    const doc = await docRef.get();
    if (!doc.exists) {
      return res.status(404).json({ error: "not_found" });
    }

    const data = doc.data() || {};
    if (!canApprove(req.user, data)) {
      return res.status(403).json({ error: "forbidden" });
    }
    if (data.estado !== "pendiente") {
      return res.status(400).json({ error: "invalid_state" });
    }

    await docRef.update({
      estado: "rechazada",
      aprobadorId: req.user.email,
      fechaAprobacion: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ ok: true });
  } catch (err) {
    console.error("requests_reject_error", err);
    res.status(500).json({ error: "requests_reject_error" });
  }
});

app.get("/balances/:userId", authMiddleware, async (req, res) => {
  try {
    const userId = normalizeText(req.params.userId);
    if (!userId) {
      return res.status(400).json({ error: "missing_user" });
    }

    if (req.user.role === "empleado" && userId !== req.user.uid) {
      return res.status(403).json({ error: "forbidden" });
    }

    const balance = await getBalance(userId);
    res.json({ balance });
  } catch (err) {
    console.error("balances_get_error", err);
    res.status(500).json({ error: "balances_get_error" });
  }
});

app.get("/calendar", authMiddleware, async (req, res) => {
  try {
    const requestedDept = normalizeText(req.query.departamentoId);
    const requestedDeptList = normalizeText(req.query.departamentoIds);
    const deptIds = requestedDeptList
      ? requestedDeptList
          .split(",")
          .map((d) => d.trim())
          .filter(Boolean)
      : requestedDept
      ? [requestedDept]
      : [];
    const includePending = normalizeText(req.query.includePending) === "1";
    const start = parseDateInput(req.query.from);
    const end = parseDateInput(req.query.to);
    if (!start || !end) {
      return res.status(400).json({ error: "invalid_dates" });
    }

    let query = db.collection(REQUESTS_COLLECTION);

    if (req.user.role === "empleado") {
      query = query.where("userId", "==", req.user.uid);
    } else if (req.user.role === "responsable") {
      query = query.where("departamentoId", "==", req.user.departamentoId || "");
    } else {
      if (deptIds.length === 1) {
        query = query.where("departamentoId", "==", deptIds[0]);
      } else if (deptIds.length > 1 && deptIds.length <= 10) {
        query = query.where("departamentoId", "in", deptIds);
      }
    }

    const snapshot = await query.get();
    const items = snapshot.docs
      .map((doc) => mapRequestDoc(doc))
      .filter((item) => {
        if (includePending) {
          if (!["aprobada", "pendiente"].includes(item.estado)) {
            return false;
          }
        } else {
          if (item.estado !== "aprobada") {
            return false;
          }
        }
        if (
          deptIds.length > 0 &&
          req.user.role !== "empleado" &&
          req.user.role !== "responsable"
        ) {
          if (!deptIds.includes(item.departamentoId || "")) {
            return false;
          }
        }
        const s = parseDateInput(item.fechaInicioStr);
        const e = parseDateInput(item.fechaFinStr);
        if (!s || !e) return false;
        return s <= end && e >= start;
      });

    res.json({ items });
  } catch (err) {
    console.error("calendar_error", err);
    res.status(500).json({ error: "calendar_error" });
  }
});

app.get("/holidays", authMiddleware, async (req, res) => {
  try {
    const year = Number(req.query.year || 0);
    if (!Number.isFinite(year) || year <= 0) {
      return res.status(400).json({ error: "invalid_year" });
    }

    const snapshot = await db
      .collection(HOLIDAYS_COLLECTION)
      .where("year", "==", year)
      .get();

    const items = snapshot.docs.map((doc) => doc.data());
    res.json({ items });
  } catch (err) {
    console.error("holidays_list_error", err);
    res.status(500).json({ error: "holidays_list_error" });
  }
});

app.put("/holidays", authMiddleware, async (req, res) => {
  try {
    if (req.user.role !== "admin") {
      return res.status(403).json({ error: "forbidden" });
    }

    const year = Number(req.body?.year || 0);
    const dates = Array.isArray(req.body?.dates) ? req.body.dates : [];
    if (!Number.isFinite(year) || year <= 0) {
      return res.status(400).json({ error: "invalid_year" });
    }

    const cleaned = dates
      .map((d) => normalizeText(d))
      .filter((d) => !!parseDateInput(d));

    const snapshot = await db
      .collection(HOLIDAYS_COLLECTION)
      .where("year", "==", year)
      .get();

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    cleaned.forEach((date) => {
      const docRef = db.collection(HOLIDAYS_COLLECTION).doc();
      batch.set(docRef, { year, date });
    });

    await batch.commit();
    res.json({ ok: true, count: cleaned.length });
  } catch (err) {
    console.error("holidays_update_error", err);
    res.status(500).json({ error: "holidays_update_error" });
  }
});

app.get("/departments", authMiddleware, async (_req, res) => {
  try {
    const snapshot = await db.collection(DEPARTMENTS_COLLECTION).get();
    const items = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ items });
  } catch (err) {
    console.error("departments_list_error", err);
    res.status(500).json({ error: "departments_list_error" });
  }
});

app.post("/departments", authMiddleware, async (req, res) => {
  try {
    if (req.user.role !== "admin") {
      return res.status(403).json({ error: "forbidden" });
    }

    const name = normalizeText(req.body?.name);
    const responsableId = normalizeText(req.body?.responsableId) || null;
    if (!name) {
      return res.status(400).json({ error: "missing_name" });
    }

    const docRef = await db.collection(DEPARTMENTS_COLLECTION).add({
      name,
      responsableId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ id: docRef.id });
  } catch (err) {
    console.error("departments_create_error", err);
    res.status(500).json({ error: "departments_create_error" });
  }
});

function normalizeText(value) {
  if (value === null || value === undefined) return "";
  return value.toString().trim();
}

function toIsoString(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  return value.toString();
}

function parseDateInput(value) {
  const raw = normalizeText(value);
  if (!raw) return null;
  const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!year || !month || !day) return null;
  const date = new Date(Date.UTC(year, month - 1, day));
  return Number.isNaN(date.getTime()) ? null : date;
}

function toDateKey(date) {
  const y = date.getUTCFullYear().toString().padStart(4, "0");
  const m = (date.getUTCMonth() + 1).toString().padStart(2, "0");
  const d = date.getUTCDate().toString().padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function timestampToDate(ts, fallbackStr) {
  if (ts && typeof ts.toDate === "function") {
    return ts.toDate();
  }
  return parseDateInput(fallbackStr);
}

function mapRequestDoc(doc) {
  const data = doc.data() || {};
  const email = data.userEmail || null;
  const displayName =
    data.userDisplayName ||
    (email ? displayNameFor(email) : null) ||
    null;
  return {
    id: doc.id,
    userId: data.userId || null,
    userEmail: email,
    userDisplayName: displayName,
    departamentoId: data.departamentoId || null,
    tipo: data.tipo || "vacaciones",
    fechaInicioStr: data.fechaInicioStr || null,
    fechaFinStr: data.fechaFinStr || null,
    estado: data.estado || "pendiente",
    aprobadorId: data.aprobadorId || null,
    fechaAprobacion: data.fechaAprobacion || null,
    notas: data.notas || null,
    diasConsumidos: Number(data.diasConsumidos || 0),
    createdAt: toIsoString(data.createdAt),
  };
}

function displayNameFor(email) {
  if (!email) return null;
  const user = usersByEmail.get(email.toLowerCase());
  if (user && user.displayName) return user.displayName;
  return null;
}

function canApprove(user, requestData) {
  if (user.role === "admin" || user.role === "responsable_general") {
    return true;
  }
  if (user.role === "responsable") {
    return (
      requestData.departamentoId &&
      user.departamentoId &&
      requestData.departamentoId === user.departamentoId
    );
  }
  return false;
}

async function hasOverlap(userId, start, end, excludeId) {
  const snapshot = await db
    .collection(REQUESTS_COLLECTION)
    .where("userId", "==", userId)
    .get();

  for (const doc of snapshot.docs) {
    if (excludeId && doc.id === excludeId) continue;
    const data = doc.data() || {};
    if (!["pendiente", "aprobada"].includes(data.estado)) {
      continue;
    }
    const s = timestampToDate(data.fechaInicio, data.fechaInicioStr);
    const e = timestampToDate(data.fechaFin, data.fechaFinStr);
    if (!s || !e) continue;
    if (s <= end && e >= start) {
      return true;
    }
  }

  return false;
}

async function countConsumableDays(start, end) {
  const holidaySet = await loadHolidaySet(start, end);
  let count = 0;
  let cursor = new Date(start.getTime());
  while (cursor <= end) {
    const key = toDateKey(cursor);
    if (!isWeekend(cursor) && !holidaySet.has(key)) {
      count += 1;
    }
    cursor = new Date(cursor.getTime() + 86400000);
  }
  return count;
}

function isWeekend(date) {
  const day = date.getUTCDay();
  return day === 0 || day === 6;
}

async function loadHolidaySet(start, end) {
  const years = [];
  for (let y = start.getUTCFullYear(); y <= end.getUTCFullYear(); y += 1) {
    years.push(y);
  }

  const set = new Set();
  for (const year of years) {
    const snapshot = await db
      .collection(HOLIDAYS_COLLECTION)
      .where("year", "==", year)
      .get();
    snapshot.docs.forEach((doc) => {
      const data = doc.data() || {};
      const date = normalizeText(data.date);
      if (date) set.add(date);
    });
  }

  return set;
}

async function getBalance(userId) {
  const docRef = db.collection(BALANCES_COLLECTION).doc(userId);
  const doc = await docRef.get();
  if (!doc.exists) {
    const initial = {
      diasAsignadosAnual: DEFAULT_ANNUAL_DAYS,
      diasArrastrados: 0,
      diasConsumidos: 0,
      diasDisponibles: DEFAULT_ANNUAL_DAYS,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await docRef.set(initial);
    return { userId, ...initial };
  }

  const data = doc.data() || {};
  const diasAsignadosAnual = Number(data.diasAsignadosAnual || DEFAULT_ANNUAL_DAYS);
  const diasArrastrados = Number(data.diasArrastrados || 0);
  const diasConsumidos = Number(data.diasConsumidos || 0);
  const diasDisponibles = diasAsignadosAnual + diasArrastrados - diasConsumidos;

  return {
    userId,
    diasAsignadosAnual,
    diasArrastrados,
    diasConsumidos,
    diasDisponibles,
  };
}

async function adjustBalance(userId, deltaConsumidos) {
  const docRef = db.collection(BALANCES_COLLECTION).doc(userId);
  const balance = await getBalance(userId);
  const diasConsumidos = Math.max(0, Number(balance.diasConsumidos || 0) + deltaConsumidos);
  const diasAsignadosAnual = Number(balance.diasAsignadosAnual || DEFAULT_ANNUAL_DAYS);
  const diasArrastrados = Number(balance.diasArrastrados || 0);
  const diasDisponibles = diasAsignadosAnual + diasArrastrados - diasConsumidos;

  await docRef.set(
    {
      diasAsignadosAnual,
      diasArrastrados,
      diasConsumidos,
      diasDisponibles,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function authMiddleware(req, res, next) {
  try {
    const auth = req.headers.authorization || "";
    if (!auth.startsWith("Bearer ")) {
      return res.status(401).json({ error: "missing_token" });
    }

    const token = auth.replace("Bearer ", "").trim();
    const decoded = await admin.auth().verifyIdToken(token);
    const email = (decoded.email || "").toLowerCase();
    if (!email.endsWith(`@${ALLOWED_DOMAIN}`)) {
      return res.status(403).json({ error: "domain_not_allowed" });
    }

    const user = usersByEmail.get(email);
    if (!user) {
      return res.status(403).json({ error: "user_not_allowed" });
    }

    req.user = {
      uid: decoded.uid,
      email,
      role: user.role,
      departamentoId: user.departamentoId || null,
      displayName: user.displayName || null,
    };
    next();
  } catch (err) {
    console.error("auth_error", err);
    res.status(401).json({ error: "invalid_token" });
  }
}

app.listen(PORT, () => {
  console.log(`Backend running on port ${PORT}`);
});
