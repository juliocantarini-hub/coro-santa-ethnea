import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useObra, marcarProgreso } from '../../hooks/useObras'
import { useAuth } from '../../hooks/useAuth'
import { DriveVisor } from '../../components/drive/DriveComponents'
import { supabase } from '../../lib/supabase'

const PROGRESO_OPTS = [
  { valor: 'pendiente',   label: 'Pendiente',   color: '#888780', bg: '#F1EFE8' },
  { valor: 'en_progreso', label: 'En progreso', color: '#D85A30', bg: '#FAECE7' },
  { valor: 'estudiada',   label: 'Estudiada ✓', color: '#27500A', bg: '#EAF3DE' },
]

const VOCES_LABELS = {
  general:   'DEMO',
  soprano:   'Soprano',
  contralto: 'Contralto',
  tenor:     'Tenor',
  bajo:      'Bajo',
}

function etiquetaAudio(audio, conteoPorVoz) {
  if (audio.etiqueta) return audio.etiqueta
  if (audio.voz === 'general') return 'DEMO'
  const label = VOCES_LABELS[audio.voz] || audio.voz
  const total = conteoPorVoz[audio.voz] || 1
  return total > 1 ? `${label} ${audio.parte}` : label
}

function useEsMovil() {
  const [esMovil, setEsMovil] = useState(window.innerWidth <= 768)
  useEffect(() => {
    const fn = () => setEsMovil(window.innerWidth <= 768)
    window.addEventListener('resize', fn)
    return () => window.removeEventListener('resize', fn)
  }, [])
  return esMovil
}

async function registrarActividad(usuarioId, obraId, tipo) {
  try {
    await supabase.from('actividad_estudio').insert({ usuario_id: usuarioId, obra_id: obraId, tipo })
  } catch (e) {}
}

export default function ObraDetalle() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { usuario, perfil } = useAuth()
  const { obra, cargando, error } = useObra(id)
  const esMovil = useEsMovil()
  const [progreso, setProgreso] = useState(null)
  const [guardando, setGuardando] = useState(false)
  const [mensajeGuardado, setMensajeGuardado] = useState('')
  const [audioSeleccionado, setAudioSeleccionado] = useState(null)

  useEffect(() => {
    if (obra && usuario) {
      registrarActividad(usuario.id, id, 'apertura')
    }
  }, [obra, usuario, id])

  // Cuando carga la obra, preseleccionar el audio de la voz del cantante
  useEffect(() => {
    if (!obra?.audios?.length || !perfil?.voz) return
    // Si ya hay selección manual, no pisar
    if (audioSeleccionado) return
    // Buscar audios de su voz
    const desuVoz = obra.audios.filter(a => a.voz === perfil.voz)
    if (desuVoz.length === 1) {
      // Solo una parte: preseleccionar automáticamente
      setAudioSeleccionado(desuVoz[0])
    }
    // Si hay más de una parte (S1/S2), NO preseleccionar — el cantante elige
  }, [obra, perfil])

  const progresoActual = progreso ?? obra?.progreso ?? 'pendiente'

  async function cambiarProgreso(nuevoEstado) {
    if (!usuario || guardando) return
    setGuardando(true)
    const { ok } = await marcarProgreso(usuario.id, id, nuevoEstado)
    if (ok) {
      setProgreso(nuevoEstado)
      setMensajeGuardado('Guardado')
      setTimeout(() => setMensajeGuardado(''), 2000)
    }
    setGuardando(false)
  }

  if (cargando) {
    return (
      <div>
        <div style={{ height: '24px', width: '120px', background: '#F1EFE8', borderRadius: '6px', marginBottom: '20px', animation: 'pulse 1.5s ease-in-out infinite' }} />
        <div style={{ height: '60px', background: '#F1EFE8', borderRadius: '10px', marginBottom: '12px', animation: 'pulse 1.5s ease-in-out infinite' }} />
        <div style={{ height: '400px', background: '#F1EFE8', borderRadius: '10px', animation: 'pulse 1.5s ease-in-out infinite' }} />
        <style>{`@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}`}</style>
      </div>
    )
  }

  if (error || !obra) {
    return (
      <div style={{ textAlign: 'center', padding: '48px 24px' }}>
        <p style={{ color: '#A32D2D', marginBottom: '16px' }}>{error || 'No encontramos esta obra.'}</p>
        <button onClick={() => navigate('/repertorio')}
          style={{ color: '#0F6E56', background: 'none', border: 'none', cursor: 'pointer', fontWeight: '500' }}>
          ← Volver al repertorio
        </button>
      </div>
    )
  }

  const audiosDisponibles = obra.audios || []

  // Conteo de partes por voz para mostrar etiquetas numeradas
  const conteoPorVoz = audiosDisponibles.reduce((acc, a) => {
    acc[a.voz] = (acc[a.voz] || 0) + 1
    return acc
  }, {})

  // Audio a reproducir: selección manual > ninguno (si su voz tiene varias partes > el cantante elige)
  const audioMostrado = audioSeleccionado || null

  // ¿Tiene audios de su voz con múltiples partes? → mostrar aviso
  const partesDesuVoz = perfil?.voz
    ? audiosDisponibles.filter(a => a.voz === perfil.voz)
    : []
  const tieneMultiplesParte = partesDesuVoz.length > 1

  function PanelAudios() {
    if (!audiosDisponibles.length) return null
    return (
      <div style={{ background: '#FFFFFF', border: '1px solid #E8E6DF', borderRadius: '12px', padding: '14px' }}>
        <div style={{ fontSize: '11px', fontWeight: '600', color: '#5F5E5A', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '10px' }}>
          Audios
        </div>

        {tieneMultiplesParte && !audioSeleccionado && (
          <div style={{ background: '#E6F1FB', border: '1px solid #B8D4F0', borderRadius: '8px', padding: '8px 12px', marginBottom: '10px', fontSize: '12px', color: '#042C53' }}>
            El director asignó tu parte en el ensayo. Elegí cuál corresponde.
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: esMovil ? 'row' : 'column', flexWrap: 'wrap', gap: '6px', marginBottom: audioMostrado ? '12px' : '0' }}>
          {audiosDisponibles.map(audio => {
            const esDesuVoz = audio.voz === perfil?.voz
            const seleccionado = audioMostrado?.voz === audio.voz && audioMostrado?.parte === audio.parte
            const label = etiquetaAudio(audio, conteoPorVoz)
            return (
              <button key={`${audio.voz}-${audio.parte}`}
                onClick={() => setAudioSeleccionado(audio)}
                style={{
                  padding: esMovil ? '6px 12px' : '7px 10px',
                  borderRadius: '8px', fontSize: '12px', cursor: 'pointer',
                  textAlign: 'left',
                  border: `1.5px solid ${seleccionado ? '#0F6E56' : esDesuVoz ? '#D85A30' : '#D3D1C7'}`,
                  background: seleccionado ? '#E1F5EE' : esDesuVoz ? '#FAECE7' : '#FFFFFF',
                  color: seleccionado ? '#04342C' : esDesuVoz ? '#712B13' : '#5F5E5A',
                  fontWeight: seleccionado || esDesuVoz ? '600' : '400',
                  display: 'flex', alignItems: 'center', gap: '6px',
                }}>
                {esDesuVoz && <span style={{ fontSize: '10px' }}>★</span>}
                {label}
              </button>
            )
          })}
        </div>

        {audioMostrado && (
          <iframe
            key={`${audioMostrado.voz}-${audioMostrado.parte}-${audioMostrado.drive_id}`}
            src={`https://drive.google.com/file/d/${audioMostrado.drive_id}/preview`}
            width="100%"
            height="80px"
            allow="autoplay"
            style={{ border: 'none', borderRadius: '8px', display: 'block' }}
          />
        )}
      </div>
    )
  }

  return (
    <div>
      <button onClick={() => navigate('/repertorio')}
        style={{ display: 'flex', alignItems: 'center', gap: '6px', color: '#888780', background: 'none', border: 'none', cursor: 'pointer', fontSize: '13px', marginBottom: '16px', padding: 0 }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
          <path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/>
        </svg>
        Volver al repertorio
      </button>

      {/* Cabecera */}
      <div style={{ background: '#FFFFFF', border: '1px solid #E8E6DF', borderRadius: '12px', padding: '20px', marginBottom: '16px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '12px', flexWrap: 'wrap' }}>
          <div>
            <h2 style={{ fontFamily: 'Georgia, serif', fontSize: '22px', fontWeight: 'normal', color: '#1A1A18', margin: '0 0 4px' }}>
              {obra.titulo}
            </h2>
            <p style={{ fontSize: '14px', color: '#888780', margin: '0 0 10px' }}>
              {obra.compositor || 'Compositor desconocido'}
            </p>
            <EstadoBadge estado={obra.estado} />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', alignItems: 'flex-end' }}>
            <span style={{ fontSize: '11px', color: '#B4B2A9', textTransform: 'uppercase', letterSpacing: '0.4px' }}>Mi progreso</span>
            <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', justifyContent: 'flex-end' }}>
              {PROGRESO_OPTS.map(op => (
                <button key={op.valor} onClick={() => cambiarProgreso(op.valor)} disabled={guardando}
                  style={{ padding: '5px 10px', borderRadius: '6px', fontSize: '11px', cursor: guardando ? 'not-allowed' : 'pointer', border: `1px solid ${progresoActual === op.valor ? op.color : '#D3D1C7'}`, background: progresoActual === op.valor ? op.bg : 'none', color: progresoActual === op.valor ? op.color : '#888780', fontWeight: progresoActual === op.valor ? '600' : '400' }}>
                  {op.label}
                </button>
              ))}
            </div>
            {mensajeGuardado && <span style={{ fontSize: '11px', color: '#639922' }}>✓ {mensajeGuardado}</span>}
          </div>
        </div>
      </div>

      {/* Móvil */}
      {esMovil && (
        <>
          <div style={{ marginBottom: '14px' }}><PanelAudios /></div>

          {obra.notas_director && (
            <div style={{ background: '#FFFFFF', border: '1px solid #E8E6DF', borderRadius: '12px', padding: '14px', marginBottom: '14px' }}>
              <div style={{ fontSize: '11px', fontWeight: '600', color: '#5F5E5A', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '8px' }}>
                Notas del director
              </div>
              <div style={{ fontSize: '12px', color: '#3D1608', lineHeight: '1.6', fontStyle: 'italic', background: '#FAECE7', borderLeft: '3px solid #D85A30', borderRadius: '0 6px 6px 0', padding: '8px 10px' }}>
                "{obra.notas_director}"
              </div>
            </div>
          )}

          <DriveVisor
            fileId={obra.drive_partitura_id}
            titulo={obra.titulo}
            onAbrir={() => usuario && registrarActividad(usuario.id, id, 'partitura_abierta')}
          />
        </>
      )}

      {/* Desktop */}
      {!esMovil && (
        <div style={{ display: 'flex', gap: '14px', alignItems: 'flex-start' }}>
          <div style={{ flex: '1 1 300px', minWidth: 0 }}>
            <DriveVisor
              fileId={obra.drive_partitura_id}
              titulo={obra.titulo}
              onAbrir={() => usuario && registrarActividad(usuario.id, id, 'partitura_abierta')}
            />
          </div>
          <div style={{ width: '240px', flexShrink: 0, display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <PanelAudios />
            {obra.notas_director && (
              <div style={{ background: '#FFFFFF', border: '1px solid #E8E6DF', borderRadius: '12px', padding: '14px' }}>
                <div style={{ fontSize: '11px', fontWeight: '600', color: '#5F5E5A', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '8px' }}>
                  Notas del director
                </div>
                <div style={{ fontSize: '12px', color: '#3D1608', lineHeight: '1.6', fontStyle: 'italic', background: '#FAECE7', borderLeft: '3px solid #D85A30', borderRadius: '0 6px 6px 0', padding: '8px 10px' }}>
                  "{obra.notas_director}"
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

function EstadoBadge({ estado }) {
  const map = {
    estudio:   { bg: '#E1F5EE', color: '#04342C', txt: 'En estudio' },
    activo:    { bg: '#EAF3DE', color: '#27500A', txt: 'Activo' },
    concierto: { bg: '#FAECE7', color: '#712B13', txt: 'Próximo ensayo' },
    archivado: { bg: '#F1EFE8', color: '#888780', txt: 'Archivado' },
  }
  const b = map[estado] || map.archivado
  return (
    <span style={{ background: b.bg, color: b.color, fontSize: '11px', fontWeight: '600', padding: '3px 10px', borderRadius: '10px' }}>
      {b.txt}
    </span>
  )
}